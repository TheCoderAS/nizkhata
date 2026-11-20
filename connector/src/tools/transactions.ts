import { z } from 'zod';

import { Books, UserError, toTxn } from '../books.js';
import { DELETE, newDocId, type Plain } from '../firestore.js';
import { computeTotal, financialYearOf, needsCategory, needsDebt, parseWhen, type Line } from '../ledger.js';
import { DESTRUCTIVE, READ, WRITE, dateArg, day, run, workspaceArg, type Register } from './common.js';

/** How a caller describes a line. A transfer is one line here; it is stored as the app's balancing pair. */
export const lineInput = z.object({
  type: z
    .enum(['expense', 'income', 'transfer', 'fee', 'tax', 'interest_income', 'interest_expense', 'lend', 'borrow', 'repayment'])
    .describe(
      'expense/income/fee/tax/interest_*: needs category_id of the right kind. transfer: moves money to to_account_id. ' +
        'lend/borrow/repayment: money against a debt, needs debt_id and the transaction contact_id.',
    ),
  amount: z.number().positive().describe('Always positive; the type decides the direction'),
  category_id: z.string().optional(),
  to_account_id: z.string().optional().describe('For transfer: the account the money goes to'),
  debt_id: z.string().optional(),
  note: z.string().optional(),
});
export type LineInput = z.infer<typeof lineInput>;

/**
 * Validate [inputs] as the app's line editor does and turn them into stored
 * lines (lineMapsFromDrafts): a transfer becomes transfer_out plus the
 * transfer_in that credits the destination.
 */
export async function buildLines(
  b: Books,
  inputs: LineInput[],
  accountId: string,
  contactId: string | undefined,
): Promise<Line[]> {
  if (!inputs.length) throw new UserError('A transaction needs at least one line.');
  const [accounts, categories, debts] = await Promise.all([b.load('accounts'), b.load('categories'), b.debts()]);
  const accountIds = new Set(accounts.map((a) => String(a.id)));
  if (!accountIds.has(accountId)) throw new UserError(`No account with id ${accountId}. Call list_accounts.`);
  const cats = new Map(categories.map((c) => [String(c.id), c]));
  const debtsById = new Map(debts.map((d) => [d.id, d]));
  const micros = Date.now() * 1000;
  const out: Line[] = [];
  inputs.forEach((l, i) => {
    const n = i + 1;
    const amount = b.round(l.amount);
    if (!(amount > 0)) throw new UserError(`Line ${n}: the amount must be more than 0.`);
    if (l.type === 'transfer') {
      if (!l.to_account_id) throw new UserError(`Line ${n}: a transfer needs to_account_id.`);
      if (!accountIds.has(l.to_account_id)) throw new UserError(`Line ${n}: no account with id ${l.to_account_id}.`);
      if (l.to_account_id === accountId) throw new UserError(`Line ${n}: the destination must differ from the account.`);
      out.push({ lineId: `l${i}_${micros}`, type: 'transfer_out', amount, ...(l.note ? { note: l.note } : {}) });
      out.push({ lineId: `l${i}b_${micros}`, type: 'transfer_in', amount, toAccountId: l.to_account_id });
      return;
    }
    const line: Line = { lineId: `l${i}_${micros}`, type: l.type, amount };
    if (needsCategory(l.type)) {
      if (l.category_id) {
        const c = cats.get(l.category_id);
        if (!c) throw new UserError(`Line ${n}: no category with id ${l.category_id}. Call list_categories.`);
        const wanted = l.type === 'income' || l.type === 'interest_income' ? 'income' : 'expense';
        if (c.kind !== wanted) throw new UserError(`Line ${n}: "${c.name}" is an ${c.kind} category; this line needs an ${wanted} one.`);
        line.categoryId = l.category_id;
      }
    }
    if (needsDebt(l.type)) {
      if (!contactId) throw new UserError(`Line ${n}: set contact_id on the transaction before linking a debt.`);
      if (!l.debt_id) throw new UserError(`Line ${n}: ${l.type} needs debt_id.`);
      const d = debtsById.get(l.debt_id);
      if (!d) throw new UserError(`Line ${n}: no debt with id ${l.debt_id}. Call list_debts.`);
      if (d.contactId !== contactId) throw new UserError(`Line ${n}: that debt belongs to someone else.`);
      line.debtId = l.debt_id;
    }
    if (l.note) line.note = l.note;
    out.push(line);
  });
  // Totals come from the stored lines, exactly as the app computes them.
  return out;
}

const txnFields = {
  account_id: z.string().describe('The account the money moves in or out of (list_accounts)'),
  date: dateArg('When it happened').optional(),
  note: z.string().optional().describe('What it was, e.g. "Groceries at Fresh Mart"'),
  contact_id: z.string().optional().describe('Who it was with (list_contacts); required for lend/borrow/repayment lines'),
  lines: z.array(lineInput).min(1).describe('One line for a simple entry; several to split one payment'),
};

export const registerTransactionTools: Register = (server, ctx) => {
  server.registerTool(
    'list_transactions',
    {
      title: 'List transactions',
      description:
        'Transactions, newest first. total is the signed effect on the account: positive in, negative out. Filter by date range, account, contact, category, type or text.',
      inputSchema: {
        ...workspaceArg,
        from: dateArg('From (inclusive)').optional(),
        to: dateArg('To (inclusive)').optional(),
        account_id: z.string().optional(),
        contact_id: z.string().optional(),
        category_id: z.string().optional(),
        type: z.enum(['income', 'expense', 'transfer']).optional().describe('Only transactions with a line of this kind'),
        search: z.string().optional().describe('Match on note'),
        limit: z.number().int().min(1).max(500).optional().describe('Default 50'),
      },
      annotations: READ,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const tz = ctx().timeZone;
        const [txns, cats, contacts, accounts] = await Promise.all([b.txns(), b.load('categories'), b.load('contacts'), b.load('accounts')]);
        const catName = new Map(cats.map((c) => [String(c.id), String(c.name)]));
        const contactName = new Map(contacts.map((c) => [String(c.id), String(c.name)]));
        const accountName = new Map(accounts.map((c) => [String(c.id), String(c.name)]));
        const from = a.from ? parseWhen(a.from, tz) : undefined;
        const to = a.to ? new Date(parseWhen(a.to, tz).getTime() + (a.to.length === 10 ? 86_400_000 : 1)) : undefined;
        const q = a.search?.toLowerCase();
        const rows = txns
          .filter((t) => !from || t.date >= from)
          .filter((t) => !to || t.date < to)
          .filter((t) => !a.account_id || t.accountId === a.account_id || t.lines.some((l) => l.toAccountId === a.account_id))
          .filter((t) => !a.contact_id || t.contactId === a.contact_id)
          .filter((t) => !a.category_id || t.lines.some((l) => l.categoryId === a.category_id))
          .filter((t) => !a.type || t.lines.some((l) => (a.type === 'transfer' ? l.type.startsWith('transfer') : a.type === 'income' ? l.type === 'income' || l.type === 'interest_income' : ['expense', 'fee', 'tax', 'interest_expense'].includes(l.type))))
          .filter((t) => !q || (t.note ?? '').toLowerCase().includes(q))
          .sort((x, y) => y.date.getTime() - x.date.getTime());
        const limit = a.limit ?? 50;
        return {
          currency: b.ws.currency,
          count: rows.length,
          showing: Math.min(limit, rows.length),
          transactions: rows.slice(0, limit).map((t) => ({
            id: t.id,
            date: day(t.date, tz),
            note: t.note,
            account: accountName.get(t.accountId) ?? (t.accountId === '__external__' ? 'Outside your accounts' : t.accountId),
            contact: t.contactId ? contactName.get(t.contactId) : undefined,
            total: t.totalAmount,
            lines: t.lines
              .filter((l) => l.type !== 'transfer_in')
              .map((l) => ({
                type: l.type === 'transfer_out' ? 'transfer' : l.type,
                amount: l.amount,
                category: l.categoryId ? catName.get(l.categoryId) : undefined,
                to_account:
                  l.type === 'transfer_out'
                    ? accountName.get(t.lines.find((p) => p.type === 'transfer_in' && Math.abs(p.amount - l.amount) < 0.005)?.toAccountId ?? '')
                    : undefined,
              })),
            ...(t.dueId ? { due_id: t.dueId } : {}),
          })),
        };
      }),
  );

  server.registerTool(
    'get_transaction',
    {
      title: 'Get a transaction',
      description: 'One transaction with every line as stored.',
      inputSchema: { ...workspaceArg, transaction_id: z.string() },
      annotations: READ,
    },
    ({ workspace_id, transaction_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const t = toTxn(await b.getOne('transactions', transaction_id));
        return { currency: b.ws.currency, ...t, date: day(t.date, ctx().timeZone) };
      }),
  );

  server.registerTool(
    'create_transaction',
    {
      title: 'Add a transaction',
      description:
        'Record money in or out of an account. One line for a simple entry (e.g. an expense with its category); several lines split one payment. Amounts are in the workspace currency.',
      inputSchema: { ...workspaceArg, ...txnFields },
      annotations: WRITE,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const tz = ctx().timeZone;
        if (a.contact_id) await b.getOne('contacts', a.contact_id);
        const lines = await buildLines(b, a.lines, a.account_id, a.contact_id);
        const debtsById = new Map((await b.debts()).map((d) => [d.id, d]));
        const date = parseWhen(a.date, tz);
        const id = newDocId();
        const doc = b.txnDoc(id, {
          date,
          accountId: a.account_id,
          totalAmount: computeTotal(lines, debtsById, b.round),
          lines,
          note: a.note?.trim() || null,
          contactId: a.contact_id ?? null,
        });
        doc.financialYear = financialYearOf(date, b.ws.fyStartMonth, tz);
        await b.commit(
          [{ kind: 'set', collection: 'transactions', id, data: doc }, b.revision('transactions', id, 'create')],
          'add transactions',
        );
        return { created: true, id, date: day(date, tz), total: doc.totalAmount, currency: b.ws.currency };
      }),
  );

  server.registerTool(
    'update_transaction',
    {
      title: 'Update a transaction',
      description:
        'Change a transaction. Fields not given keep their value; giving lines replaces all of them. Pass null for note or contact_id to clear it.',
      inputSchema: {
        ...workspaceArg,
        transaction_id: z.string(),
        account_id: z.string().optional(),
        date: dateArg('When it happened').optional(),
        note: z.string().nullable().optional(),
        contact_id: z.string().nullable().optional(),
        lines: z.array(lineInput).min(1).optional(),
      },
      annotations: WRITE,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const tz = ctx().timeZone;
        const cur = await b.getOne('transactions', a.transaction_id);
        const old = toTxn(cur);
        const accountId = a.account_id ?? old.accountId;
        const contactId = a.contact_id === null ? undefined : (a.contact_id ?? old.contactId);
        if (a.contact_id) await b.getOne('contacts', a.contact_id);
        const lines = a.lines ? await buildLines(b, a.lines, accountId, contactId) : old.lines;
        const debtsById = new Map((await b.debts()).map((d) => [d.id, d]));
        const date = a.date ? parseWhen(a.date, tz) : old.date;
        const note = a.note === null ? undefined : (a.note?.trim() || old.note);
        // As updateTransaction: every field written, optional ones deleted when absent.
        const data: Plain = {
          date,
          accountId,
          totalAmount: computeTotal(lines, debtsById, b.round),
          hasSplit: lines.length > 1,
          financialYear: financialYearOf(date, b.ws.fyStartMonth, tz),
          lines: lines.map((l) => Object.fromEntries(Object.entries(l).filter(([, v]) => v !== undefined && v !== null))),
          note: note ?? DELETE,
          contactId: contactId ?? DELETE,
          dueId: cur.dueId ?? DELETE,
          recurrence: cur.recurrence ?? DELETE,
          notePattern: cur.notePattern ?? DELETE,
        };
        const writes = b.updateWrites('transactions', a.transaction_id, data, false);
        await b.commit(writes, 'edit transactions');
        return { updated: true, id: a.transaction_id, total: data.totalAmount };
      }),
  );

  server.registerTool(
    'delete_transaction',
    {
      title: 'Delete a transaction',
      description: 'Remove a transaction; balances, debts and dues update to match. Cannot be undone from here.',
      inputSchema: { ...workspaceArg, transaction_id: z.string() },
      annotations: DESTRUCTIVE,
    },
    ({ workspace_id, transaction_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const t = toTxn(await b.getOne('transactions', transaction_id));
        await b.commit(b.deleteWrites('transactions', transaction_id), 'delete transactions');
        return { deleted: true, id: transaction_id, note: t.note, total: t.totalAmount };
      }),
  );
};
