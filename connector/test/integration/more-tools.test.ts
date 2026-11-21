// Accounts, reports, bulk recategorise, history with restore, and the shared
// ledger: against the emulator running the real firestore.rules, as members.

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';

import { Books } from '../../src/books.js';
import { Firestore, type Plain } from '../../src/firestore.js';
import { buildMcpServer } from '../../src/server.js';
import type { Ctx } from '../../src/tools/common.js';

const PROJECT = process.env.GCLOUD_PROJECT ?? 'rules-test';
const HOST = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const BASE = `http://${HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;
const TZ = 'Asia/Kolkata';

function idToken(uid: string): string {
  const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${b64({ alg: 'none', typ: 'JWT' })}.${b64({
    iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT, sub: uid, user_id: uid,
    iat: now, exp: now + 3600, auth_time: now, email: `${uid}@example.com`, email_verified: true,
    firebase: { sign_in_provider: 'google.com' },
  })}.`;
}

const admin = new Firestore(BASE, 'owner');
const PERMS = [
  'transactions.view', 'transactions.create', 'transactions.edit', 'transactions.delete',
  'accounts.view', 'accounts.manage', 'categories.view', 'categories.manage',
  'contacts.view', 'contacts.manage', 'debts.view', 'debts.manage', 'dues.view', 'dues.manage',
  'shared.view', 'shared.manage', 'reports.view', 'reports.export',
  'members.view', 'members.invite', 'members.remove', 'roles.view', 'roles.manage', 'workspace.edit', 'workspace.delete',
];
const perms = (on: (p: string) => boolean) => Object.fromEntries(PERMS.map((p) => [p, on(p)]));
const set = (collection: string, id: string, data: Plain) => ({ kind: 'set' as const, collection, id, data: { id, ...data } });

async function asUser(uid: string, name: string) {
  const fs = new Firestore(BASE, idToken(uid));
  const actor = { uid, name };
  const ctx: Ctx = { fs, actor, email: `${uid}@example.com`, timeZone: TZ, books: (w?: string) => Books.open(fs, actor, TZ, w) };
  const [a, b] = InMemoryTransport.createLinkedPair();
  await buildMcpServer(() => ctx).connect(a);
  const client = new Client({ name: 'test', version: '1' });
  await client.connect(b);
  const call = async (tool: string, args: Record<string, unknown> = {}) => {
    const r = (await client.callTool({ name: tool, arguments: args })) as { content: Array<{ text: string }>; isError?: boolean };
    const text = r.content[0]!.text;
    if (r.isError) return { error: text } as Record<string, any>;
    return JSON.parse(text) as Record<string, any>;
  };
  return { call, close: () => client.close() };
}

const doc = (c: string, id: string) => admin.get(c, id) as Promise<Plain>;

let asha: Awaited<ReturnType<typeof asUser>>;
let ravi: Awaited<ReturnType<typeof asUser>>;

beforeAll(async () => {
  await admin.commit([
    // Asha's books
    set('workspaces', 'wa', { name: 'Asha home', ownerId: 'asha', baseCurrency: 'INR', fyStartMonth: 4 }),
    set('roles', 'wa_owner', { workspaceId: 'wa', name: 'Owner', isSystem: true, permissions: perms(() => true) }),
    set('memberships', 'wa_asha', { workspaceId: 'wa', uid: 'asha', roleId: 'wa_owner', status: 'active' }),
    set('accounts', 'wa_bank', { workspaceId: 'wa', name: 'SBI', type: 'bank', openingBalance: 50000 }),
    set('categories', 'wa_food', { workspaceId: 'wa', name: 'Food', kind: 'expense', isSystem: true }),
    set('categories', 'wa_fun', { workspaceId: 'wa', name: 'Fun', kind: 'expense', isSystem: false }),
    set('categories', 'wa_pay', { workspaceId: 'wa', name: 'Salary', kind: 'income', isSystem: true }),
    // Ravi's books, in rupees too
    set('workspaces', 'wr', { name: 'Ravi home', ownerId: 'ravi', baseCurrency: 'INR', fyStartMonth: 4 }),
    set('roles', 'wr_owner', { workspaceId: 'wr', name: 'Owner', isSystem: true, permissions: perms(() => true) }),
    set('memberships', 'wr_ravi', { workspaceId: 'wr', uid: 'ravi', roleId: 'wr_owner', status: 'active' }),
    set('accounts', 'wr_bank', { workspaceId: 'wr', name: 'ICICI', type: 'bank', openingBalance: 10000 }),
    // They share a ledger
    set('sharedConnections', 'asha_ravi', {
      uids: ['asha', 'ravi'], names: { asha: 'Asha', ravi: 'Ravi' }, emails: { asha: 'asha@example.com', ravi: 'ravi@example.com' }, status: 'active',
    }),
  ]);
  asha = await asUser('asha', 'Asha');
  ravi = await asUser('ravi', 'Ravi');
});
afterAll(async () => {
  await asha?.close();
  await ravi?.close();
});

describe('accounts', () => {
  it('adds a credit card with its billing cycle, lists it, edits it, refuses bank fields on cards', async () => {
    const r = await asha.call('create_account', {
      name: 'HDFC Regalia', type: 'credit_card', opening_balance: -2500, credit_limit: 150000, statement_day: 25, payment_due_day: 12, card_last4: '4821',
    });
    expect(await doc('accounts', r.id)).toMatchObject({
      workspaceId: 'wa', name: 'HDFC Regalia', type: 'credit_card', openingBalance: -2500,
      creditLimit: 150000, statementDay: 25, paymentDueDay: 12, cardLast4: '4821', createdBy: { uid: 'asha', name: 'Asha' },
    });
    const listed = (await asha.call('list_accounts')).accounts.find((a: any) => a.id === r.id);
    expect(listed).toMatchObject({ balance: -2500, statement_day: 25, payment_due_day: 12, card_last4: '4821', credit_limit: 150000 });

    expect((await asha.call('create_account', { name: 'Cash', type: 'cash', credit_limit: 5 })).error).toMatch(/only apply to credit cards/);
    expect((await asha.call('create_account', { name: 'Card', type: 'credit_card', statement_day: 5 })).error).toMatch(/together/);

    await asha.call('update_account', { account_id: r.id, statement_day: null, payment_due_day: null, name: 'Regalia' });
    const after = await doc('accounts', r.id);
    expect(after.name).toBe('Regalia');
    expect('statementDay' in after).toBe(false);
  });

  it('deletes and restores an account under the same id', async () => {
    const r = await asha.call('create_account', { name: 'Wallet', type: 'cash', opening_balance: 700 });
    expect((await asha.call('delete_account', { account_id: r.id })).deleted).toBe(true);
    expect(await admin.get('accounts', r.id)).toBeNull();
    const act = await asha.call('list_activity', { entity_id: r.id });
    expect(act.entries[0]).toMatchObject({ action: 'delete', type: 'accounts', restorable: true, about: 'Wallet' });
    const rs = await asha.call('restore_deleted', { entity_id: r.id });
    expect(rs.error ?? rs.restored).toBe(true);
    expect(await doc('accounts', r.id)).toMatchObject({ name: 'Wallet', type: 'cash', openingBalance: 700 });
    expect((await asha.call('restore_deleted', { entity_id: r.id })).error).toMatch(/not deleted/);
  });
});

describe('reports and recategorise', () => {
  it('summarises a period like the Reports screen, then recategorises in bulk', async () => {
    const add = (lines: unknown[], date: string, note: string) =>
      asha.call('create_transaction', { account_id: 'wa_bank', date, note, lines });
    const t1 = await add([{ type: 'expense', amount: 1200 }], '2026-10-03', 'Swiggy');
    const t2 = await add([{ type: 'expense', amount: 800 }, { type: 'fee', amount: 20 }], '2026-10-09', 'Zomato');
    await add([{ type: 'income', amount: 90000, category_id: 'wa_pay' }], '2026-10-01', 'Salary');
    await add([{ type: 'expense', amount: 3000, category_id: 'wa_fun' }], '2026-10-20', 'Movie');
    await add([{ type: 'expense', amount: 999, category_id: 'wa_fun' }], '2026-11-02', 'Next month');

    const s = await asha.call('get_summary', { from: '2026-10-01', to: '2026-10-31' });
    expect(s).toMatchObject({ from: '2026-10-01', to: '2026-10-31', transactions: 4, income: 90000, expense: 5020, net: 84980, spending_uncategorised: 2020 });
    expect(s.spending_by_category).toEqual([{ category_id: 'wa_fun', category: 'Fun', amount: 3000 }]);
    expect(s.accounts).toEqual([{ account_id: 'wa_bank', account: 'SBI', money_in: 90000, money_out: 5020, net: 84980 }]);
    expect(s.trend.by).toBe('day');

    const r = await asha.call('recategorise_transactions', { transaction_ids: [t1.id, t2.id], category_id: 'wa_food' });
    expect(r).toMatchObject({ transactions_changed: 2, lines_changed: 2 });
    // Only the expense lines got it; the fee line stays as it was.
    expect(((await doc('transactions', t2.id)).lines as Plain[]).map((l) => l.categoryId ?? null)).toEqual(['wa_food', null]);
    const revs = await admin.where('revisions', 'entityId', t1.id);
    expect(revs.find((x) => x.action === 'update')).toMatchObject({ changedFields: ['lines'] });

    const moved = await asha.call('recategorise_transactions', { transaction_ids: [t1.id], category_id: 'wa_fun', from_category_id: 'wa_food' });
    expect(moved.lines_changed).toBe(1);
    expect((await asha.call('recategorise_transactions', { transaction_ids: [t1.id], category_id: 'wa_pay', from_category_id: 'wa_fun' })).error).toMatch(/not the same kind/);

    const after = await asha.call('get_summary', { from: '2026-10-01', to: '2026-10-31' });
    expect(after.spending_by_category).toEqual([
      { category_id: 'wa_fun', category: 'Fun', amount: 4200 },
      { category_id: 'wa_food', category: 'Food', amount: 800 },
    ]);
  });
});

describe('history and restore', () => {
  it('restores a deleted transaction exactly, and rebuilds one from its history when the delete kept nothing', async () => {
    const t = await asha.call('create_transaction', {
      account_id: 'wa_bank', date: '2026-11-05', note: 'Groceries', lines: [{ type: 'expense', amount: 640, category_id: 'wa_food' }],
    });
    const before = await doc('transactions', t.id);
    await asha.call('delete_transaction', { transaction_id: t.id });
    expect((await asha.call('restore_deleted', { entity_id: t.id })).restored).toBe(true);
    const back = await doc('transactions', t.id);
    expect(back).toMatchObject({ totalAmount: -640, note: 'Groceries', accountId: 'wa_bank', lines: before.lines, financialYear: '2026-27' });
    expect((back.date as Date).getTime()).toBe((before.date as Date).getTime());

    // A contact created, edited and deleted in an older app (no snapshot on the delete).
    const c = await asha.call('create_contact', { name: 'Meera', phone: '+91 90000 00000' });
    await asha.call('update_contact', { contact_id: c.id, notes: 'Neighbour', phone: null });
    await admin.commit([
      { kind: 'delete', collection: 'contacts', id: c.id },
      set('revisions', `old_del_${c.id}`, { workspaceId: 'wa', entityType: 'contacts', entityId: c.id, action: 'delete', by: { uid: 'asha', name: 'Asha' }, at: new Date() }),
    ]);
    expect((await asha.call('restore_deleted', { entity_id: c.id })).restored).toBe(true);
    const rebuilt = await doc('contacts', c.id);
    expect(rebuilt).toMatchObject({ name: 'Meera', notes: 'Neighbour' });
    expect('phone' in rebuilt).toBe(false);

    const feed = await asha.call('list_activity', { limit: 5 });
    expect(feed.entries[0]).toMatchObject({ action: 'create', type: 'contacts', by: 'Asha' });
  });
});

describe('shared ledger', () => {
  it('Asha splits a dinner with Ravi; Ravi accepts; Ravi settles; Asha confirms', async () => {
    const listed = await asha.call('list_shared');
    expect(listed.partners).toEqual([{ partner_id: 'ravi', name: 'Ravi', email: 'ravi@example.com' }]);

    const add = await asha.call('add_shared_expense', {
      description: 'Dinner at Bastian', amount: 3000, account_id: 'wa_bank', partners: [{ partner: 'Ravi' }], my_category_id: 'wa_food', date: '2026-11-10',
    });
    expect(add).toMatchObject({ my_share: 1500, entries: [{ with: 'Ravi', share: 1500 }] });
    const entryId = add.entries[0].entry_id;
    expect(await doc('sharedEntries', entryId)).toMatchObject({
      kind: 'expense', creatorUid: 'asha', counterpartyUid: 'ravi', payerUid: 'asha', amount: 1500, currency: 'INR', status: 'pending', pendingForUids: ['ravi'],
    });
    // Asha's books: her own share as an expense, Ravi's as a lend against a hidden shared debt.
    const mine = (await admin.where('transactions', 'workspaceId', 'wa')).filter((t) => String(t.note ?? '').startsWith('Dinner'));
    expect(mine.map((t) => t.totalAmount).sort()).toEqual([-1500, -1500]);
    const reflection = mine.find((t) => t.sharedEntryId === entryId)!;
    expect((reflection.lines as Plain[])[0]).toMatchObject({ type: 'lend', amount: 1500, lineId: `lend_${entryId}` });
    const contact = await doc('contacts', String(reflection.contactId));
    expect(contact).toMatchObject({ connectionUid: 'ravi', name: 'Ravi', type: 'person' });

    expect((await asha.call('list_shared')).balances).toEqual([{ partner_id: 'ravi', partner: 'Ravi', currency: 'INR', net: 1500, meaning: 'Ravi is to pay you' }]);
    expect((await asha.call('respond_shared_entry', { entry_id: entryId, accept: true })).error).toMatch(/only the other person/);

    // Ravi sees it waiting, and accepts: a balance-only borrow in his books.
    const theirs = await ravi.call('list_shared');
    expect(theirs.entries[0]).toMatchObject({ id: entryId, waiting_for_you: true, with: 'Asha' });
    expect((await ravi.call('respond_shared_entry', { entry_id: entryId, accept: true })).accepted).toBe(true);
    expect((await doc('sharedEntries', entryId)).status).toBe('accepted');
    const rt = (await admin.where('transactions', 'workspaceId', 'wr')).find((t) => t.sharedEntryId === entryId)!;
    expect(rt).toMatchObject({ accountId: '__external__', totalAmount: 0 });
    expect((rt.lines as Plain[])[0]).toMatchObject({ type: 'borrow', amount: 1500, external: true });
    expect((await ravi.call('list_shared')).balances[0]).toMatchObject({ net: -1500, meaning: 'you are to pay Asha' });

    // Ravi pays her back from his bank; Asha confirms it arrived in SBI.
    const st = await ravi.call('record_shared_settlement', { partner: 'asha@example.com', amount: 1500, account_id: 'wr_bank' });
    const raviBank = (await ravi.call('list_accounts')).accounts.find((a: any) => a.id === 'wr_bank');
    expect(raviBank.balance).toBe(8500);
    expect((await asha.call('respond_shared_entry', { entry_id: st.entry_id, accept: true, account_id: 'wa_bank' })).accepted).toBe(true);
    expect((await asha.call('list_shared')).balances).toEqual([]);
    expect((await ravi.call('list_shared')).balances).toEqual([]);
  });

  it('refuses a partner you do not share with, and an entry in another currency', async () => {
    expect((await asha.call('add_shared_expense', { description: 'x', amount: 10, account_id: 'wa_bank', partners: [{ partner: 'Kabir' }] })).error).toMatch(/No shared ledger with "Kabir"/);
    await admin.commit([
      set('sharedEntries', 'usd_entry', {
        connectionId: 'asha_ravi', kind: 'expense', uids: ['ravi', 'asha'], creatorUid: 'ravi', counterpartyUid: 'asha', names: { ravi: 'Ravi', asha: 'Asha' },
        payerUid: 'ravi', description: 'NYC taxi', amount: 40, currency: 'USD', date: new Date(), status: 'pending', pendingForUids: ['asha'], createdBy: { uid: 'ravi', name: 'Ravi' },
      }),
    ]);
    expect((await asha.call('respond_shared_entry', { entry_id: 'usd_entry', accept: true })).error).toMatch(/in USD.*never converted/);
    expect((await asha.call('respond_shared_entry', { entry_id: 'usd_entry', accept: false })).rejected).toBe(true);
  });
});

describe('repeating dues and time zones', () => {
  it('stop_repeating_due ends a series from that due onward and keeps what exists', async () => {
    const first = await asha.call('create_due', { title: 'Netflix', direction: 'payable', amount: 649, due_date: '2026-10-05', repeats: 'monthly' });
    const nov = `rec_${first.id}_20261105`;
    const dec = `rec_${first.id}_20261205`;
    await admin.commit([
      set('dues', nov, { workspaceId: 'wa', direction: 'payable', title: 'Netflix', amount: 649, status: 'open', recurrence: 'monthly', recurrenceId: first.id, dueDate: new Date('2026-11-04T18:30:00Z') }),
      set('dues', dec, { workspaceId: 'wa', direction: 'payable', title: 'Netflix', amount: 649, status: 'open', recurrence: 'monthly', recurrenceId: first.id, dueDate: new Date('2026-12-04T18:30:00Z') }),
    ]);
    const r = await asha.call('stop_repeating_due', { due_id: nov });
    expect(r.dues_changed.sort()).toEqual([dec, nov].sort());
    expect('recurrence' in (await doc('dues', nov))).toBe(false);
    expect('recurrence' in (await doc('dues', dec))).toBe(false);
    expect((await doc('dues', first.id)).recurrence).toBe('monthly'); // October's is history, untouched
    expect((await asha.call('stop_repeating_due', { due_id: nov })).error).toMatch(/does not repeat/);
  });

  it('dates in a workspace are its own days', async () => {
    await admin.commit([
      set('workspaces', 'wny', { name: 'NY books', ownerId: 'asha', baseCurrency: 'USD', fyStartMonth: 1, timeZone: 'America/New_York' }),
      set('roles', 'wny_owner', { workspaceId: 'wny', name: 'Owner', isSystem: true, permissions: perms(() => true) }),
      set('memberships', 'wny_asha', { workspaceId: 'wny', uid: 'asha', roleId: 'wny_owner', status: 'active' }),
      set('accounts', 'wny_chase', { workspaceId: 'wny', name: 'Chase', type: 'bank', openingBalance: 0 }),
    ]);
    const ws = (await asha.call('list_workspaces')).find((w: any) => w.id === 'wny');
    expect(ws.time_zone).toBe('America/New_York');
    const t = await asha.call('create_transaction', { workspace_id: 'wny', account_id: 'wny_chase', date: '2026-11-20', lines: [{ type: 'income', amount: 10 }] });
    expect(((await doc('transactions', t.id)).date as Date).toISOString()).toBe('2026-11-20T05:00:00.000Z'); // midnight in New York
    expect((await asha.call('get_transaction', { workspace_id: 'wny', transaction_id: t.id })).date).toBe('2026-11-20');
    // An Indian workspace still means Indian midnight.
    const i = await asha.call('create_transaction', { workspace_id: 'wa', account_id: 'wa_bank', date: '2026-11-20', lines: [{ type: 'income', amount: 10, category_id: 'wa_pay' }] });
    expect(((await doc('transactions', i.id)).date as Date).toISOString()).toBe('2026-11-19T18:30:00.000Z');
  });
});

describe('dues split over several lines', () => {
  it('creates, part-pays and edits a split due as the app does', async () => {
    const r = await asha.call('create_due', {
      workspace_id: 'wa',
      title: 'Flat: rent and maintenance', due_date: '2026-12-01', account_id: 'wa_bank',
      lines: [
        { type: 'expense', amount: 15000, category_id: 'wa_food' },
        { type: 'fee', amount: 1500, category_id: 'wa_fun' },
      ],
    });
    expect(r).toMatchObject({ created: true, direction: 'payable', amount: 16500, lines: 2 });
    const d = await doc('dues', r.id);
    expect(d).toMatchObject({ direction: 'payable', amount: 16500, categoryId: 'wa_food', accountId: 'wa_bank', status: 'open' });
    expect((d.lines as Plain[]).map((l) => [l.type, l.amount])).toEqual([['expense', 15000], ['fee', 1500]]);

    // A part payment carries both lines, scaled to what was paid.
    const p = await asha.call('record_due_payment', { workspace_id: 'wa', due_id: r.id, account_id: 'wa_bank', amount: 8250 });
    expect(p).toMatchObject({ due_status: 'partial', left: 8250 });
    const t = await doc('transactions', p.transaction_id);
    expect((t.lines as Plain[]).map((l) => [l.type, l.amount])).toEqual([['expense', 7500], ['fee', 750]]);

    // A single amount cannot be set on a split due; giving its lines again can.
    expect((await asha.call('update_due', { workspace_id: 'wa', due_id: r.id, amount: 20000 })).error).toMatch(/give all its lines again/);
    const u = await asha.call('update_due', {
      workspace_id: 'wa',
      due_id: r.id,
      lines: [{ type: 'expense', amount: 16000, category_id: 'wa_food' }, { type: 'fee', amount: 2000, category_id: 'wa_fun' }],
    });
    expect(u.updated).toBe(true);
    expect(await doc('dues', r.id)).toMatchObject({ amount: 18000, direction: 'payable' });
    // The payment already made is kept in step, still 8,250, split the new way.
    const t2 = await doc('transactions', p.transaction_id);
    expect(t2.totalAmount).toBe(-8250);
  });

  it('works out receivable from income lines, and refuses what does not add up', async () => {
    const r = await asha.call('create_due', {
      workspace_id: 'wa',
      title: 'Freelance invoice', due_date: '2026-12-10', account_id: 'wa_bank',
      lines: [{ type: 'income', amount: 40000, category_id: 'wa_pay' }, { type: 'tax', amount: 4000, category_id: 'wa_food' }],
    });
    expect(r).toMatchObject({ direction: 'receivable', amount: 36000 });
    expect((await asha.call('create_due', { workspace_id: 'wa', title: 'x', due_date: '2026-12-10', lines: [{ type: 'income', amount: 1, category_id: 'wa_pay' }] })).error).toMatch(/needs account_id/);
    expect((await asha.call('create_due', { workspace_id: 'wa', title: 'x', due_date: '2026-12-10', account_id: 'wa_bank', amount: 5, lines: [{ type: 'income', amount: 1, category_id: 'wa_pay' }] })).error).toMatch(/leave out amount/);
    expect((await asha.call('create_due', { workspace_id: 'wa', title: 'x', due_date: '2026-12-10', account_id: 'wa_bank', direction: 'payable', lines: [{ type: 'income', amount: 1, category_id: 'wa_pay' }] })).error).toMatch(/receivable due, not a payable/);
    expect((await asha.call('create_due', { workspace_id: 'wa', title: 'x', due_date: '2026-12-10' })).error).toMatch(/Give direction and amount, or lines/);
    // The single-amount form still works as before.
    expect((await asha.call('create_due', { workspace_id: 'wa', title: 'Gym', direction: 'payable', amount: 1500, due_date: '2026-12-05' })).amount).toBe(1500);
  });
});
