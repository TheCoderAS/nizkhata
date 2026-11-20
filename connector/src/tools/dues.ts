import { z } from 'zod';

import { UserError, strip, type Books } from '../books.js';
import { newDocId, type Plain, type Write } from '../firestore.js';
import { computeTotal, dueSettledAmount, dueStatusFromSettled, financialYearOf, parseWhen, type Line } from '../ledger.js';
import { DESTRUCTIVE, READ, WRITE, dateArg, day, run, workspaceArg, type Register } from './common.js';

const direction = z
  .enum(['payable', 'receivable'])
  .describe('payable: you pay it (rent, a bill). receivable: someone pays you.');

/** A due's single line, as the due form stores one: expense for payable, income for receivable. */
function dueLine(dir: string, amount: number, categoryId: string | undefined): Line {
  return {
    lineId: `l0_${Date.now() * 1000}`,
    type: dir === 'payable' ? 'expense' : 'income',
    amount,
    ...(categoryId ? { categoryId } : {}),
  };
}

async function checkCategory(b: Books, categoryId: string | undefined, dir: string) {
  if (!categoryId) return;
  const c = await b.getOne('categories', categoryId);
  const wanted = dir === 'payable' ? 'expense' : 'income';
  if (c.kind !== wanted) throw new UserError(`"${c.name}" is an ${c.kind} category; a ${dir} due needs an ${wanted} one.`);
}

/** buildDueSettlement (mobile/lib/data/due_settlement.dart). */
function settlement(b: Books, due: Plain, amount: number, debtsById: Map<string, never>, seed: number) {
  const lines = ((due.lines as Plain[] | undefined) ?? []) as unknown as Line[];
  const dueAmount = Number(due.amount ?? 0);
  if (lines.length && dueAmount > 0.005) {
    const f = amount / dueAmount;
    const out = lines.map((l, i) => {
      const m: Line = { ...l, lineId: `due_${seed}_l${i}`, amount: b.round(Number(l.amount) * f) };
      const tax = m.tax as Plain | undefined;
      if (tax && typeof tax.tdsAmount === 'number') m.tax = { ...tax, tdsAmount: b.round((tax.tdsAmount as number) * f) };
      return m;
    });
    const unit = computeTotal(lines, debtsById, b.round);
    return { lines: out, signedTotal: b.round(Math.sign(unit) * amount) };
  }
  const payable = due.direction === 'payable';
  return {
    lines: [{ lineId: `due_${seed}`, type: payable ? 'expense' : 'income', amount, ...(due.categoryId ? { categoryId: String(due.categoryId) } : {}) }] as Line[],
    signedTotal: b.round(payable ? -amount : amount),
  };
}

export const registerDueTools: Register = (server, ctx) => {
  server.registerTool(
    'list_dues',
    {
      title: 'List dues',
      description:
        'Upcoming and past dues (bills to pay, money to receive) with how much is paid and left. Defaults to unsettled ones (open or part paid), soonest first.',
      inputSchema: {
        ...workspaceArg,
        status: z.enum(['unsettled', 'open', 'partial', 'settled', 'cancelled', 'all']).optional(),
        direction: direction.optional(),
        from: dateArg('Due on or after').optional(),
        to: dateArg('Due on or before').optional(),
        contact_id: z.string().optional(),
      },
      annotations: READ,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const tz = ctx().timeZone;
        const [dues, txns, contacts] = await Promise.all([b.dues(), b.txns(), b.load('contacts')]);
        const names = new Map(contacts.map((c) => [String(c.id), String(c.name)]));
        const from = a.from ? parseWhen(a.from, tz) : undefined;
        const to = a.to ? new Date(parseWhen(a.to, tz).getTime() + (a.to.length === 10 ? 86_400_000 : 1)) : undefined;
        const want = a.status ?? 'unsettled';
        const rows = dues
          .map((d) => {
            const settled = dueSettledAmount(d, txns, b.round);
            return { d, settled, status: dueStatusFromSettled(d, settled) };
          })
          .filter((r) => want === 'all' || (want === 'unsettled' ? r.status === 'open' || r.status === 'partial' : r.status === want))
          .filter((r) => !a.direction || r.d.direction === a.direction)
          .filter((r) => !a.contact_id || r.d.contactId === a.contact_id)
          .filter((r) => !from || (r.d.dueDate as Date) >= from)
          .filter((r) => !to || (r.d.dueDate as Date) < to)
          .sort((x, y) => (x.d.dueDate as Date).getTime() - (y.d.dueDate as Date).getTime());
        return {
          currency: b.ws.currency,
          dues: rows.map(({ d, settled, status }) => ({
            id: d.id,
            title: d.title,
            direction: d.direction,
            amount: d.amount,
            paid: settled,
            left: b.round(Math.max(0, d.amount - settled)),
            status,
            due_date: day(d.dueDate, tz),
            contact: d.contactId ? names.get(String(d.contactId)) : undefined,
            ...(d.recurrence ? { repeats: d.recurrence } : {}),
            ...(d.statementAccountId ? { credit_card_bill: true } : {}),
          })),
        };
      }),
  );

  server.registerTool(
    'create_due',
    {
      title: 'Add a due',
      description: 'Add a bill to pay or money to receive on a date, optionally repeating.',
      inputSchema: {
        ...workspaceArg,
        title: z.string().min(1),
        direction,
        amount: z.number().positive(),
        due_date: dateArg('When it is due'),
        contact_id: z.string().optional(),
        account_id: z.string().optional().describe('The account it is usually paid from or into'),
        category_id: z.string().optional(),
        note: z.string().optional(),
        repeats: z.enum(['weekly', 'monthly', 'yearly']).optional(),
      },
      annotations: WRITE,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const tz = ctx().timeZone;
        if (a.contact_id) await b.getOne('contacts', a.contact_id);
        if (a.account_id) await b.getOne('accounts', a.account_id);
        await checkCategory(b, a.category_id, a.direction);
        const amount = b.round(a.amount);
        const dueDate = parseWhen(a.due_date, tz);
        // The due form's payload, with createDue's status.
        const data: Plain = {
          direction: a.direction,
          title: a.title.trim(),
          titlePattern: null,
          notePattern: null,
          occurrence: 1,
          amount,
          dueDate,
          contactId: a.contact_id ?? null,
          accountId: a.account_id ?? null,
          categoryId: a.category_id ?? null,
          note: a.note?.trim() || null,
          lines: [dueLine(a.direction, amount, a.category_id)],
          recurrence: a.repeats ?? null,
          recurrenceId: null,
          status: 'open',
        };
        const { id, writes } = b.createWrites('dues', data);
        await b.commit(writes, 'add dues');
        return { created: true, id, title: data.title, amount, due_date: day(dueDate, tz) };
      }),
  );

  server.registerTool(
    'update_due',
    {
      title: 'Update a due',
      description:
        'Change a due. Fields not given keep their value; pass null to clear an optional one. status "cancelled" withdraws it, "open" brings a cancelled one back. Payments already recorded against it are updated to match, as in the app.',
      inputSchema: {
        ...workspaceArg,
        due_id: z.string(),
        title: z.string().min(1).optional(),
        amount: z.number().positive().optional(),
        due_date: dateArg('When it is due').optional(),
        contact_id: z.string().nullable().optional(),
        account_id: z.string().nullable().optional(),
        category_id: z.string().nullable().optional(),
        note: z.string().nullable().optional(),
        repeats: z.enum(['weekly', 'monthly', 'yearly']).nullable().optional(),
        status: z.enum(['open', 'cancelled']).optional(),
      },
      annotations: WRITE,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const tz = ctx().timeZone;
        const due = await b.getOne('dues', a.due_id);
        const dir = String(due.direction);
        const lines = ((due.lines as Plain[] | undefined) ?? []) as unknown as Line[];
        if (a.contact_id) await b.getOne('contacts', a.contact_id);
        if (a.account_id) await b.getOne('accounts', a.account_id);
        if (a.category_id) await checkCategory(b, a.category_id, dir);
        const data: Plain = {};
        if (a.title !== undefined) data.title = a.title.trim();
        if (a.due_date !== undefined) data.dueDate = parseWhen(a.due_date, tz);
        if (a.contact_id !== undefined) data.contactId = a.contact_id;
        if (a.account_id !== undefined) data.accountId = a.account_id;
        if (a.note !== undefined) data.note = a.note?.trim() || null;
        if (a.repeats !== undefined) {
          data.recurrence = a.repeats;
          data.recurrenceId = a.repeats ? (due.recurrenceId ?? a.due_id) : null;
        }
        if (a.status !== undefined) data.status = a.status;
        const touchesLines = a.amount !== undefined || a.category_id !== undefined;
        if (touchesLines) {
          if (lines.length > 1) throw new UserError('This due is split into several lines; change its amount or category in the app.');
          const amount = a.amount !== undefined ? b.round(a.amount) : Number(due.amount);
          const categoryId = a.category_id !== undefined ? (a.category_id ?? undefined) : (lines[0]?.categoryId ?? (due.categoryId as string | undefined));
          data.amount = amount;
          data.categoryId = categoryId ?? null;
          data.lines = [{ ...dueLine(dir, amount, categoryId), ...(lines[0] ? { lineId: lines[0].lineId } : {}) }];
        }
        if (!Object.keys(data).length) throw new UserError('Nothing to change.');
        const writes: Write[] = b.updateWrites('dues', a.due_id, data);

        // syncDueLinkedTxns: payments already made carry the due's lines,
        // scaled to what each one paid, and its note and contact.
        const linked = (await b.txns()).filter((t) => t.dueId === a.due_id);
        if (linked.length) {
          const debtsById = new Map((await b.debts()).map((d) => [d.id, d]));
          const merged = { ...due, ...data };
          const dueLines = ((merged.lines as Plain[] | undefined) ?? []) as unknown as Line[];
          const signedTotal = computeTotal(dueLines, debtsById, b.round);
          const title = String(merged.title ?? '');
          const note = (merged.note as string | null | undefined) || (title || null);
          for (const t of linked) {
            let newLines: Line[];
            let signed: number;
            if (dueLines.length && Math.abs(signedTotal) > 0.005) {
              const f = Math.abs(t.totalAmount) / Math.abs(signedTotal);
              newLines = dueLines.map((l, i) => ({ ...l, lineId: `${t.id}_l${i}`, amount: b.round(Number(l.amount) * f) }));
              signed = b.round(Math.sign(signedTotal) * Math.abs(t.totalAmount));
            } else {
              newLines = t.lines;
              signed = (dir === 'payable' ? -1 : 1) * Math.abs(t.totalAmount);
            }
            writes.push(
              ...b.updateWrites('transactions', t.id, {
                lines: newLines.map((l) => strip(l as unknown as Plain)),
                totalAmount: signed,
                note,
                contactId: (merged.contactId as string | null | undefined) ?? null,
              }, false),
            );
          }
        }
        await b.commit(writes, 'edit dues');
        return { updated: true, id: a.due_id, changed: Object.keys(data), payments_updated: linked.length };
      }),
  );

  server.registerTool(
    'delete_due',
    {
      title: 'Delete a due',
      description: 'Remove a due. Payments already recorded stay as transactions. Cannot be undone from here; to withdraw it instead, use update_due with status "cancelled".',
      inputSchema: { ...workspaceArg, due_id: z.string() },
      annotations: DESTRUCTIVE,
    },
    ({ workspace_id, due_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const d = await b.getOne('dues', due_id);
        await b.commit(b.deleteWrites('dues', due_id), 'delete dues');
        return { deleted: true, id: due_id, title: d.title };
      }),
  );

  server.registerTool(
    'record_due_payment',
    {
      title: 'Record a payment on a due',
      description:
        'Pay a due, or record money received on it, from an account. Creates the transaction and marks the due part paid or settled, as the app does. amount defaults to what is left.',
      inputSchema: {
        ...workspaceArg,
        due_id: z.string(),
        account_id: z.string().optional().describe("Defaults to the due's account"),
        amount: z.number().positive().optional(),
        date: dateArg('When it was paid').optional(),
      },
      annotations: WRITE,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const tz = ctx().timeZone;
        const due = await b.getOne('dues', a.due_id);
        if (due.status === 'cancelled') throw new UserError('This due is cancelled. Reopen it with update_due first.');
        const accountId = a.account_id ?? (due.accountId as string | undefined);
        if (!accountId) throw new UserError('Which account? Pass account_id (see list_accounts).');
        await b.getOne('accounts', accountId);
        const [txns, debts] = await Promise.all([b.txns(), b.debts()]);
        const dueAmount = Number(due.amount ?? 0);
        const paid = dueSettledAmount({ id: a.due_id, amount: dueAmount, status: String(due.status) }, txns, b.round);
        const left = b.round(dueAmount - paid);
        const amount = b.round(a.amount ?? left);
        if (!(amount > 0)) throw new UserError('Nothing is left to pay on this due.');
        const date = parseWhen(a.date, tz);
        const seed = Date.now() * 1000;
        const s = settlement(b, due, amount, new Map(debts.map((d) => [d.id, d])) as Map<string, never>, seed);
        const txnId = newDocId();
        const doc = b.txnDoc(txnId, {
          date,
          accountId,
          totalAmount: s.signedTotal,
          lines: s.lines,
          note: (due.note as string | undefined) || String(due.title ?? ''),
          contactId: (due.contactId as string | undefined) ?? null,
          dueId: a.due_id,
        });
        doc.financialYear = financialYearOf(date, b.ws.fyStartMonth, tz);
        const newStatus = dueStatusFromSettled({ id: a.due_id, amount: dueAmount, status: String(due.status) }, paid + amount);
        // settleDue: the transaction and the due's status in one commit.
        const writes: Write[] = [
          { kind: 'set', collection: 'transactions', id: txnId, data: doc },
          b.revision('transactions', txnId, 'create'),
          ...b.updateWrites('dues', a.due_id, { status: newStatus }, false),
        ];
        writes[writes.length - 1] = b.revision('dues', a.due_id, 'update', undefined, ['status']);
        await b.commit(writes, 'record payments on dues');
        return { recorded: true, transaction_id: txnId, amount, due_status: newStatus, left: b.round(Math.max(0, left - amount)) };
      }),
  );
};

