import { z } from 'zod';

import { UserError } from '../books.js';
import { newDocId, SERVER_TIME, type Plain, type Write } from '../firestore.js';
import { debtOutstanding, debtStatusFrom, financialYearOf, parseWhen } from '../ledger.js';
import { DESTRUCTIVE, READ, WRITE, OVERWRITE, dateArg, day, run, workspaceArg, type Register } from './common.js';

const EXTERNAL_ACCOUNT = '__external__';

// The app stores owe (you have it to pay) / owed (it is due to you); the
// connector speaks in payable / receivable, as the app's screens do.
const toStored = (d: 'payable' | 'receivable') => (d === 'payable' ? 'owe' : 'owed');
const toShown = (d: string) => (d === 'owe' ? 'payable' : 'receivable');

const purpose = z.enum(['loan', 'custodial_savings', 'lending', 'reimbursable', 'informal']);

export const registerDebtTools: Register = (server, ctx) => {
  server.registerTool(
    'list_debts',
    {
      title: 'List debts',
      description:
        'Money lent and borrowed, per person, with what is outstanding. receivable: money due to you; payable: money you have to pay. Defaults to outstanding ones.',
      inputSchema: {
        ...workspaceArg,
        status: z.enum(['outstanding', 'settled', 'all']).optional(),
        contact_id: z.string().optional(),
      },
      annotations: READ,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const [debts, txns, contacts] = await Promise.all([b.debts(), b.txns(), b.load('contacts')]);
        const names = new Map(contacts.map((c) => [String(c.id), String(c.name)]));
        const want = a.status ?? 'outstanding';
        return {
          currency: b.ws.currency,
          debts: debts
            .filter((d) => !a.contact_id || d.contactId === a.contact_id)
            .map((d) => {
              const outstanding = debtOutstanding(d, txns, b.round);
              return { d, outstanding, status: debtStatusFrom(d, outstanding) };
            })
            .filter((r) => want === 'all' || (want === 'settled' ? r.status === 'settled' : r.status !== 'settled'))
            .map(({ d, outstanding, status }) => ({
              id: d.id,
              label: d.label,
              contact_id: d.contactId,
              contact: names.get(d.contactId),
              direction: toShown(d.direction),
              purpose: d.purpose,
              outstanding,
              status,
              ...(d.interestRate ? { interest_rate: d.interestRate } : {}),
            })),
        };
      }),
  );

  server.registerTool(
    'create_debt',
    {
      title: 'Add a debt',
      description:
        'Record money lent to or borrowed from a contact. With an amount, the opening transaction is recorded too: from account_id when the money moved through one of your accounts, or outside your accounts when it did not.',
      inputSchema: {
        ...workspaceArg,
        contact_id: z.string(),
        direction: z.enum(['receivable', 'payable']).describe('receivable: you lent it. payable: you borrowed it.'),
        amount: z.number().min(0).describe('The opening amount; 0 to record the debt with nothing yet'),
        purpose: purpose.optional().describe('Default loan'),
        label: z.string().optional(),
        note: z.string().optional(),
        interest_rate: z.number().min(0).optional().describe('Yearly %, if any'),
        account_id: z.string().optional(),
        date: dateArg('When the money moved').optional(),
      },
      annotations: WRITE,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const tz = ctx().timeZone;
        await b.getOne('contacts', a.contact_id);
        if (a.account_id) await b.getOne('accounts', a.account_id);
        const amount = b.round(a.amount);
        const when = parseWhen(a.date, tz);
        const direction = toStored(a.direction);
        // createDebtWithOpening (mutations.dart).
        const debtId = newDocId();
        const debtDoc: Plain = Object.fromEntries(
          Object.entries({
            contactId: a.contact_id,
            direction,
            purpose: a.purpose ?? 'loan',
            principal: amount,
            label: a.label?.trim() || null,
            note: a.note?.trim() || null,
            interestRate: a.interest_rate ?? null,
            interestFrom: a.interest_rate !== undefined ? new Date() : null,
            status: 'open',
          }).filter(([, v]) => v !== null),
        );
        const by = { uid: ctx().actor.uid, name: ctx().actor.name };
        const writes: Write[] = [
          {
            kind: 'set', collection: 'debts', id: debtId,
            data: { id: debtId, workspaceId: b.ws.id, ...debtDoc, createdBy: by, createdAt: SERVER_TIME, updatedBy: by, updatedAt: SERVER_TIME },
          },
          b.revision('debts', debtId, 'create', debtDoc),
        ];
        let txnId: string | undefined;
        if (amount > 0) {
          txnId = newDocId();
          const external = !a.account_id;
          const line: Plain = {
            lineId: `open_${when.getTime() * 1000}`,
            type: direction === 'owe' ? 'borrow' : 'lend',
            amount,
            debtId,
            note: 'Opening balance',
            ...(external ? { external: true } : {}),
          };
          writes.push(
            {
              kind: 'set', collection: 'transactions', id: txnId,
              data: {
                id: txnId, workspaceId: b.ws.id, date: when,
                accountId: a.account_id ?? EXTERNAL_ACCOUNT,
                contactId: a.contact_id,
                totalAmount: external ? 0 : (direction === 'owe' ? 1 : -1) * amount,
                hasSplit: false,
                financialYear: financialYearOf(when, b.ws.fyStartMonth, tz),
                note: 'Opening balance',
                createdBy: by, createdAt: SERVER_TIME, updatedBy: by, updatedAt: SERVER_TIME,
                lines: [line],
              },
            },
            b.revision('transactions', txnId, 'create'),
          );
        }
        await b.commit(writes, 'add debts');
        return { created: true, id: debtId, opening_transaction_id: txnId, outstanding: amount };
      }),
  );

  server.registerTool(
    'update_debt',
    {
      title: 'Update a debt',
      description:
        "Change a debt's label, note, interest or status. Contact, direction and purpose are fixed once created, as in the app. status 'settled' closes it even with money left (for example written off).",
      inputSchema: {
        ...workspaceArg,
        debt_id: z.string(),
        label: z.string().nullable().optional(),
        note: z.string().nullable().optional(),
        interest_rate: z.number().min(0).nullable().optional(),
        status: z.enum(['open', 'settled']).optional(),
      },
      annotations: OVERWRITE,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        await b.getOne('debts', a.debt_id);
        const data: Plain = {};
        if (a.label !== undefined) data.label = a.label?.trim() || null;
        if (a.note !== undefined) data.note = a.note?.trim() || null;
        if (a.interest_rate !== undefined) data.interestRate = a.interest_rate;
        if (a.status !== undefined) data.status = a.status;
        if (!Object.keys(data).length) throw new UserError('Nothing to change.');
        await b.commit(b.updateWrites('debts', a.debt_id, data), 'edit debts');
        return { updated: true, id: a.debt_id, changed: Object.keys(data) };
      }),
  );

  server.registerTool(
    'delete_debt',
    {
      title: 'Delete a debt',
      description: 'Stop tracking a debt. Its transactions are kept. Cannot be undone from here.',
      inputSchema: { ...workspaceArg, debt_id: z.string() },
      annotations: DESTRUCTIVE,
    },
    ({ workspace_id, debt_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const d = await b.getOne('debts', debt_id);
        await b.commit(b.deleteWrites('debts', debt_id), 'delete debts');
        return { deleted: true, id: debt_id, label: d.label };
      }),
  );

  server.registerTool(
    'record_debt_repayment',
    {
      title: 'Record a repayment',
      description:
        'Money paid back on a debt, through an account: received from them on a receivable debt, paid by you on a payable one. Closes the debt when nothing is left.',
      inputSchema: {
        ...workspaceArg,
        debt_id: z.string(),
        amount: z.number().positive(),
        account_id: z.string(),
        date: dateArg('When it was paid').optional(),
        note: z.string().optional(),
      },
      annotations: WRITE,
    },
    (a) =>
      run(async () => {
        const b = await ctx().books(a.workspace_id);
        const tz = ctx().timeZone;
        const debts = await b.debts();
        const debt = debts.find((d) => d.id === a.debt_id);
        if (!debt) throw new UserError(`No debt with id ${a.debt_id}. Call list_debts.`);
        await b.getOne('accounts', a.account_id);
        // Read before writing: a balance read afterwards would already
        // include this repayment (the bug fixed in the app in 1.12.2).
        const before = debtOutstanding(debt, await b.txns(), b.round);
        const amount = b.round(a.amount);
        const date = parseWhen(a.date, tz);
        const txnId = newDocId();
        const doc = b.txnDoc(txnId, {
          date,
          accountId: a.account_id,
          totalAmount: b.round(debt.direction === 'owe' ? -amount : amount),
          lines: [{ lineId: `rep_${Date.now() * 1000}`, type: 'repayment', amount, debtId: debt.id }],
          note: a.note?.trim() || null,
          contactId: debt.contactId,
        });
        doc.financialYear = financialYearOf(date, b.ws.fyStartMonth, tz);
        const writes: Write[] = [
          { kind: 'set', collection: 'transactions', id: txnId, data: doc },
          b.revision('transactions', txnId, 'create'),
        ];
        const settles = before - amount <= 0.005;
        if (settles) writes.push(...b.updateWrites('debts', debt.id, { status: 'settled' }));
        await b.commit(writes, 'record repayments');
        return {
          recorded: true,
          transaction_id: txnId,
          outstanding_before: before,
          outstanding_now: b.round(Math.max(0, before - amount)),
          debt_settled: settles,
          ...(day(date, tz) ? { date: day(date, tz) } : {}),
        };
      }),
  );
};
