// Accounts: the cash, bank and credit card ledgers transactions are recorded
// against. Records only: nothing here links to or moves money at a real bank.
//
// Writes the same fields the app's account form does, all of them: the bank
// details on a bank account (CIF only in INR books, as the form offers it) and
// the card's details on a credit card.

import { z } from 'zod';

import { UserError } from '../books.js';
import type { Plain } from '../firestore.js';
import { accountBalances } from '../ledger.js';
import { DESTRUCTIVE, OVERWRITE, READ, WRITE, run, workspaceArg, type Register } from './common.js';

const TYPES = ['cash', 'bank', 'credit_card'] as const;
const CARD_ONLY = ['credit_limit', 'statement_day', 'payment_due_day', 'card_last4', 'name_on_card', 'card_expiry'] as const;
const BANK_ONLY = ['account_number', 'cif', 'ifsc', 'branch_name'] as const;

const fields = {
  name: z.string().min(1).describe('What the account is called, e.g. "HDFC Savings" or "Visa Platinum".'),
  type: z.enum(TYPES),
  opening_balance: z
    .number()
    .describe('Balance when it was first entered. For a credit card, what was already owed on it, as a negative number.'),
  code: z.string().describe('A short code shown next to the name.'),
  description: z.string(),
  credit_limit: z.number().positive().describe('Credit cards only.'),
  statement_day: z.number().int().min(1).max(31).describe('Credit cards only: the day of the month the bill is generated. Needs payment_due_day too.'),
  payment_due_day: z.number().int().min(1).max(31).describe('Credit cards only: the day of the month the bill must be paid by. Needs statement_day too.'),
  card_last4: z.string().regex(/^\d{4}$/).describe('Credit cards only: the last four digits of the card.'),
  name_on_card: z.string().describe('Credit cards only.'),
  card_expiry: z.string().regex(/^(0[1-9]|1[0-2])\/\d{2}$/).describe('Credit cards only: MM/YY.'),
  account_number: z.string().describe('Bank accounts only.'),
  cif: z.string().describe('Bank accounts in INR books only: the customer ID (CIF).'),
  ifsc: z.string().describe('Bank accounts only: the IFSC, or the bank or branch code outside India.'),
  branch_name: z.string().describe('Bank accounts only.'),
};

type Input = Partial<{ [K in keyof typeof fields]: z.infer<(typeof fields)[K]> | null }>;

/** The document fields for [input]; with [existingType], an update to an account of that type. */
function toDoc(input: Input, currency: string, existingType?: string): Plain {
  const type = input.type ?? existingType;
  const given = (keys: readonly (keyof Input)[]) => keys.filter((k) => input[k] !== undefined && input[k] !== null);
  if (type !== 'credit_card' && given(CARD_ONLY).length) throw new UserError(`${given(CARD_ONLY).join(', ')} only apply to credit cards.`);
  if (type !== 'bank' && given(BANK_ONLY).length) throw new UserError(`${given(BANK_ONLY).join(', ')} only apply to bank accounts.`);
  if (input.cif && currency !== 'INR') throw new UserError('cif is for bank accounts in INR books.');
  // A cycle needs both days; the app's form stores neither of a half-filled pair.
  const s = input.statement_day;
  const d = input.payment_due_day;
  if ((s === undefined) !== (d === undefined) || (s === null) !== (d === null)) {
    throw new UserError('Give statement_day and payment_due_day together (or clear both with null).');
  }
  const doc: Plain = {};
  const map: Array<[keyof Input, string]> = [
    ['name', 'name'],
    ['type', 'type'],
    ['opening_balance', 'openingBalance'],
    ['code', 'code'],
    ['description', 'description'],
    ['credit_limit', 'creditLimit'],
    ['statement_day', 'statementDay'],
    ['payment_due_day', 'paymentDueDay'],
    ['card_last4', 'cardLast4'],
    ['name_on_card', 'nameOnCard'],
    ['card_expiry', 'cardExpiry'],
    ['account_number', 'accountNumber'],
    ['cif', 'cif'],
    ['ifsc', 'ifsc'],
    ['branch_name', 'branchName'],
  ];
  for (const [k, f] of map) {
    const v = input[k];
    if (v === undefined) continue;
    doc[f] = typeof v === 'string' ? v.trim() || null : v;
  }
  if (typeof doc.name === 'string' && !doc.name) throw new UserError('An account needs a name.');
  return doc;
}

export const registerAccountTools: Register = (server, ctx) => {
  server.registerTool(
    'list_accounts',
    {
      title: 'List accounts',
      description:
        'Cash, bank and credit card accounts in a workspace, with current balances and every detail kept on them (bank and card details). Transactions need an account_id from here. A credit card balance below zero is what is used on the card.',
      inputSchema: workspaceArg,
      annotations: READ,
    },
    ({ workspace_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const [accounts, txns, debts] = await Promise.all([b.load('accounts'), b.txns(), b.debts()]);
        const balances = accountBalances(
          accounts.map((a) => ({ id: String(a.id), openingBalance: Number(a.openingBalance ?? 0) })),
          txns,
          new Map(debts.map((d) => [d.id, d])),
          b.round,
        );
        return {
          currency: b.ws.currency,
          accounts: accounts.map((a) => ({
            id: a.id,
            name: a.name,
            type: a.type,
            balance: balances.get(String(a.id)) ?? 0,
            opening_balance: Number(a.openingBalance ?? 0),
            ...(a.code ? { code: a.code } : {}),
            ...(a.description ? { description: a.description } : {}),
            ...(a.type === 'credit_card'
              ? {
                  ...(a.creditLimit ? { credit_limit: a.creditLimit } : {}),
                  ...(a.statementDay && a.paymentDueDay
                    ? { statement_day: a.statementDay, payment_due_day: a.paymentDueDay }
                    : {}),
                  ...(a.cardLast4 ? { card_last4: a.cardLast4 } : {}),
                  ...(a.nameOnCard ? { name_on_card: a.nameOnCard } : {}),
                  ...(a.cardExpiry ? { card_expiry: a.cardExpiry } : {}),
                }
              : {}),
            ...(a.type === 'bank'
              ? {
                  ...(a.accountNumber ? { account_number: a.accountNumber } : {}),
                  ...(a.cif ? { cif: a.cif } : {}),
                  ...(a.ifsc ? { ifsc: a.ifsc } : {}),
                  ...(a.branchName ? { branch_name: a.branchName } : {}),
                }
              : {}),
          })),
        };
      }),
  );

  server.registerTool(
    'create_account',
    {
      title: 'Add an account',
      description:
        'Add a cash, bank or credit card account to keep records against. This is a ledger entry only: it does not connect to any bank. For a credit card, statement_day and payment_due_day make the app raise each month\'s card bill as a due.',
      inputSchema: {
        ...workspaceArg,
        name: fields.name,
        type: fields.type,
        opening_balance: fields.opening_balance.optional(),
        code: fields.code.optional(),
        description: fields.description.optional(),
        credit_limit: fields.credit_limit.optional(),
        statement_day: fields.statement_day.optional(),
        payment_due_day: fields.payment_due_day.optional(),
        card_last4: fields.card_last4.optional(),
        name_on_card: fields.name_on_card.optional(),
        card_expiry: fields.card_expiry.optional(),
        account_number: fields.account_number.optional(),
        cif: fields.cif.optional(),
        ifsc: fields.ifsc.optional(),
        branch_name: fields.branch_name.optional(),
      },
      annotations: WRITE,
    },
    ({ workspace_id, ...input }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const doc = toDoc(input, b.ws.currency);
        doc.openingBalance = b.round(Number(doc.openingBalance ?? 0));
        const { id, writes } = b.createWrites('accounts', doc);
        await b.commit(writes, 'add accounts');
        return { created: true, id, name: doc.name, type: doc.type };
      }),
  );

  server.registerTool(
    'update_account',
    {
      title: 'Update an account',
      description:
        'Change an account. Only the fields given change; null clears an optional one. Changing opening_balance moves the balance by the same amount.',
      inputSchema: {
        ...workspaceArg,
        account_id: z.string(),
        name: fields.name.optional(),
        type: fields.type.optional(),
        opening_balance: fields.opening_balance.optional(),
        code: fields.code.nullable().optional(),
        description: fields.description.nullable().optional(),
        credit_limit: fields.credit_limit.nullable().optional(),
        statement_day: fields.statement_day.nullable().optional(),
        payment_due_day: fields.payment_due_day.nullable().optional(),
        card_last4: fields.card_last4.nullable().optional(),
        name_on_card: fields.name_on_card.nullable().optional(),
        card_expiry: fields.card_expiry.nullable().optional(),
        account_number: fields.account_number.nullable().optional(),
        cif: fields.cif.nullable().optional(),
        ifsc: fields.ifsc.nullable().optional(),
        branch_name: fields.branch_name.nullable().optional(),
      },
      annotations: OVERWRITE,
    },
    ({ workspace_id, account_id, ...input }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const existing = await b.getOne('accounts', account_id);
        const doc = toDoc(input, b.ws.currency, String(existing.type ?? 'bank'));
        if (typeof doc.openingBalance === 'number') doc.openingBalance = b.round(doc.openingBalance);
        // Leaving credit cards behind: the card's own fields go with it.
        if (doc.type && doc.type !== 'bank' && existing.type === 'bank') {
          for (const f of ['accountNumber', 'cif', 'ifsc', 'branchName']) if (f in existing) doc[f] = null;
        }
        if (doc.type && doc.type !== 'credit_card' && existing.type === 'credit_card') {
          for (const f of ['creditLimit', 'statementDay', 'paymentDueDay', 'cardLast4', 'nameOnCard', 'cardExpiry']) {
            if (f in existing) doc[f] = null;
          }
        }
        if (Object.keys(doc).length === 0) throw new UserError('Nothing to change.');
        await b.commit(b.updateWrites('accounts', account_id, doc), 'change accounts');
        return { updated: true, id: account_id, changed: Object.keys(doc) };
      }),
  );

  server.registerTool(
    'delete_account',
    {
      title: 'Delete an account',
      description:
        'Delete an account, as the app does: its transactions are kept. It can be brought back with restore_deleted.',
      inputSchema: { ...workspaceArg, account_id: z.string() },
      annotations: DESTRUCTIVE,
    },
    ({ workspace_id, account_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const existing = await b.getOne('accounts', account_id);
        await b.commit(b.deleteWrites('accounts', account_id, existing), 'delete accounts');
        return { deleted: true, id: account_id, name: existing.name };
      }),
  );
};
