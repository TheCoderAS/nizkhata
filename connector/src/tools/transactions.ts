import { z } from 'zod';

import { Books, UserError, toTxn } from '../books.js';
import { DELETE, newDocId, type Plain } from '../firestore.js';
import { computeTotal, financialYearOf, needsCategory, needsDebt, parseWhen, type Line } from '../ledger.js';
import { calOf, hasTokens, renderTokens } from '../jobs/rules.js';
import { DESTRUCTIVE, READ, WRITE, OVERWRITE, dateArg, day, run, workspaceArg, type Register } from './common.js';

/** How a caller describes a line. A transfer is one line here; it is stored as the app's balancing pair. */
/** Tax heads, as the app's tax block offers them (mobile/lib/widgets/txn_lines_editor.dart kTaxHeads). */
export const TAX_HEADS = [
  'salary', 'bonus', 'overtime', 'reimbursement', 'perquisite', 'commission', 'professional_fees',
  'rent', 'interest', 'dividend', 'capital_gains', 'business', 'other', 'exempt',
] as const;
/** Heads that only mean something under Indian income tax. */
const INDIA_ONLY_HEADS = new Set(['perquisite']);

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
  tax: z
    .object({
      head: z.enum(TAX_HEADS).describe('What kind of income it is for tax'),
      tds_amount: z.number().min(0).optional().describe('Tax deducted at source on this line'),
      tax_inclusive: z.boolean().optional().describe('True when amount already includes the tax'),
    })
    .optional()
    .describe('Income and interest_income lines only: marks the line taxable, as the tax block in the app does.'),
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
    if (l.tax) {
      // The app's tax block: income lines only; a perquisite only in Indian books.
      if (l.type !== 'income' && l.type !== 'interest_income') {
        throw new UserError(`Line ${n}: tax applies to income and interest_income lines only.`);
      }
      if (INDIA_ONLY_HEADS.has(l.tax.head) && b.ws.currency !== 'INR') {
        throw new UserError(`Line ${n}: the "${l.tax.head}" tax head is for books kept in INR.`);
      }
      const tds = b.round(l.tax.tds_amount ?? 0);
      if (tds > amount) throw new UserError(`Line ${n}: the TDS (${tds}) cannot be more than the line (${amount}).`);
      line.tax = { taxable: true, head: l.tax.head, tdsAmount: tds, taxInclusive: l.tax.tax_inclusive ?? false };
    }
    if (l.note) line.note = l.note;
    out.push(line);
  });
  // Totals come from the stored lines, exactly as the app computes them.
  return out;
}

const NOTE_HELP =
  'May hold placeholders, as in the app: {MMM} month, {MMMM} full month, {MM}, {YYYY}, {YY}, {D}, {DD}, {DATE}, {Q}, {FY}, {#} occurrence, with offsets like {MMM-1}; {{ for a literal brace.';

const txnFields = {
  account_id: z.string().describe('The account the money moves in or out of (list_accounts)'),
  date: dateArg('When it happened').optional(),
  note: z.string().optional().describe(`What it was, e.g. "Groceries at Fresh Mart". ${NOTE_HELP}`),
  contact_id: z
    .string()
    .optional()
    .describe('Who it was with (list_contacts). Without it, a lend/borrow/repayment line takes its debt\'s contact, as in the app.'),
  lines: z.array(lineInput).min(1).describe('One line for a simple entry; several to split one payment'),
  repeats: z.enum(['weekly', 'monthly', 'yearly']).optional().describe('A repeating entry: the app suggests the next one when it is due'),
};

/** The note as the app stores it: rendered for the date, the pattern kept when it has placeholders. */
export function renderNote(b: Books, pattern: string | null | undefined, date: Date, occurrence = 1) {
  const p = pattern?.trim();
  if (!p) return { note: null, notePattern: null };
  return {
    note: renderTokens(p, calOf(date, b.timeZone), { occurrence, fyStartMonth: b.ws.fyStartMonth }),
    notePattern: hasTokens(p) ? p : null,
  };
}

/** The app's fallback: with no contact given, a debt line's contact. */
export async function contactFor(b: Books, contactId: string | undefined, inputs: LineInput[]): Promise<string | undefined> {
  if (contactId) return contactId;
  const debtLine = inputs.find((l) => l.debt_id && (l.type === 'lend' || l.type === 'borrow' || l.type === 'repayment'));
  if (!debtLine) return undefined;
  const d = (await b.debts()).find((x) => x.id === debtLine.debt_id);
  return d?.contactId;
}

/** A line's tax block for output, in the connector's own names; nothing when it has none. */
export function taxOut(l: { tax?: Record<string, unknown> }) {
  const t = l.tax;
  if (!t || t.taxable !== true) return {};
  return { tax: { head: t.head ?? 'other', tds_amount: Number(t.tdsAmount ?? 0), tax_inclusive: t.taxInclusive === true } };
}

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
        const tz = b.timeZone;
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
                ...taxOut(l),
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
        const raw = await b.getOne('transactions', transaction_id);
        const t = toTxn(raw);
        return {
          currency: b.ws.currency,
          ...t,
          date: day(t.date, b.timeZone),
          ...(raw.recurrence ? { repeats: raw.recurrence } : {}),
          ...(raw.notePattern ? { note_pattern: raw.notePattern } : {}),
        };
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
        const tz = b.timeZone;
        if (a.contact_id) await b.getOne('contacts', a.contact_id);
        const contactId = await contactFor(b, a.contact_id, a.lines);
        const lines = await buildLines(b, a.lines, a.account_id, contactId);
        const debtsById = new Map((await b.debts()).map((d) => [d.id, d]));
        const date = parseWhen(a.date, tz);
        const id = newDocId();
        const { note, notePattern } = renderNote(b, a.note, date);
        const doc = b.txnDoc(id, {
          date,
          accountId: a.account_id,
          totalAmount: computeTotal(lines, debtsById, b.round),
          lines,
          note,
          contactId: contactId ?? null,
        });
        doc.financialYear = financialYearOf(date, b.ws.fyStartMonth, tz);
        if (a.repeats) doc.recurrence = a.repeats;
        if (notePattern) doc.notePattern = notePattern;
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
        note: z.string().nullable().optional().describe(NOTE_HELP),
        contact_id: z.string().nullable().optional(),
        lines: z.array(lineInput).min(1).optional(),
        repeats: z.enum(['weekly', 'monthly', 'yearly']).nullable().optional(),
      },
      annotations: OVERWRITE,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const tz = b.timeZone;
        const cur = await b.getOne('transactions', a.transaction_id);
        const old = toTxn(cur);
        const accountId = a.account_id ?? old.accountId;
        let contactId = a.contact_id === null ? undefined : (a.contact_id ?? old.contactId);
        if (a.contact_id) await b.getOne('contacts', a.contact_id);
        if (!contactId && a.lines) contactId = await contactFor(b, undefined, a.lines);
        const lines = a.lines ? await buildLines(b, a.lines, accountId, contactId) : old.lines;
        const debtsById = new Map((await b.debts()).map((d) => [d.id, d]));
        const date = a.date ? parseWhen(a.date, tz) : old.date;
        // The note: a new one is rendered for the date; otherwise the stored
        // pattern is re-rendered, so moving the date moves "{MMM}" with it.
        const rendered =
          a.note === null
            ? { note: null, notePattern: null }
            : a.note !== undefined
              ? renderNote(b, a.note, date)
              : cur.notePattern
                ? renderNote(b, String(cur.notePattern), date)
                : { note: old.note ?? null, notePattern: null };
        const note = rendered.note ?? undefined;
        const recurrence = a.repeats === undefined ? cur.recurrence : a.repeats;
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
          recurrence: recurrence ?? DELETE,
          notePattern: rendered.notePattern ?? DELETE,
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
      description: 'Remove a transaction; balances, debts and dues update to match. It can be brought back with restore_deleted.',
      inputSchema: { ...workspaceArg, transaction_id: z.string() },
      annotations: DESTRUCTIVE,
    },
    ({ workspace_id, transaction_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const raw = await b.getOne('transactions', transaction_id);
        const t = toTxn(raw);
        await b.commit(b.deleteWrites('transactions', transaction_id, raw), 'delete transactions');
        return { deleted: true, id: transaction_id, note: t.note, total: t.totalAmount };
      }),
  );
};
