// Every tool, against the Firestore emulator running the app's real
// firestore.rules, as a signed-in member: the rules must accept each write,
// the stored documents must have the shape the app writes, and a member
// whose role forbids a change must be refused.
//
// Run: firebase emulators:exec --only firestore --project rules-test "npm run test:emulator"
// (from the repo root, so firebase.json points the emulator at firestore.rules)

import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
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
const WS = 'ws1';

/** An unsigned ID token: the emulator accepts these and applies the rules to them. */
function idToken(uid: string): string {
  const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${b64({ alg: 'none', typ: 'JWT' })}.${b64({
    iss: `https://securetoken.google.com/${PROJECT}`, aud: PROJECT, sub: uid, user_id: uid,
    iat: now, exp: now + 3600, auth_time: now, email: `${uid}@example.com`, email_verified: true,
    firebase: { sign_in_provider: 'google.com' },
  })}.`;
}

const admin = new Firestore(BASE, 'owner'); // the emulator's rules bypass

const PERMS = [
  'transactions.view', 'transactions.create', 'transactions.edit', 'transactions.delete',
  'accounts.view', 'accounts.manage', 'categories.view', 'categories.manage',
  'contacts.view', 'contacts.manage', 'debts.view', 'debts.manage', 'dues.view', 'dues.manage',
  'shared.view', 'shared.manage', 'reports.view', 'reports.export',
  'members.view', 'members.invite', 'members.remove', 'roles.view', 'roles.manage', 'workspace.edit', 'workspace.delete',
];
const perms = (on: (p: string) => boolean) => Object.fromEntries(PERMS.map((p) => [p, on(p)]));

async function seed() {
  await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  const set = (collection: string, id: string, data: Plain) => ({ kind: 'set' as const, collection, id, data: { id, ...data } });
  await admin.commit([
    set('workspaces', WS, { name: 'Home', ownerId: 'u1', baseCurrency: 'INR', fyStartMonth: 4 }),
    set('roles', `${WS}_owner`, { workspaceId: WS, name: 'Owner', isSystem: true, permissions: perms(() => true) }),
    set('roles', `${WS}_viewer`, { workspaceId: WS, name: 'Viewer', isSystem: true, permissions: perms((p) => p.endsWith('.view')) }),
    set('memberships', `${WS}_u1`, { workspaceId: WS, uid: 'u1', roleId: `${WS}_owner`, status: 'active' }),
    set('memberships', `${WS}_v1`, { workspaceId: WS, uid: 'v1', roleId: `${WS}_viewer`, status: 'active' }),
    set('accounts', 'bank', { workspaceId: WS, name: 'HDFC Savings', type: 'bank', openingBalance: 100000 }),
    set('accounts', 'card', { workspaceId: WS, name: 'Visa', type: 'credit_card', openingBalance: 0 }),
    set('categories', 'food', { workspaceId: WS, name: 'Food', kind: 'expense', isSystem: true }),
    set('categories', 'salary', { workspaceId: WS, name: 'Salary', kind: 'income', isSystem: true }),
  ]);
}

async function asUser(uid: string, name: string) {
  const fs = new Firestore(BASE, idToken(uid));
  const actor = { uid, name };
  const ctx: Ctx = { fs, actor, email: `${uid}@example.com`, timeZone: TZ, books: (w?: string) => Books.open(fs, actor, TZ, w) };
  const [a, b] = InMemoryTransport.createLinkedPair();
  await buildMcpServer(() => ctx).connect(a);
  const client = new Client({ name: 'test', version: '1' });
  await client.connect(b);
  const call = async (name: string, args: Record<string, unknown> = {}) => {
    const r = (await client.callTool({ name, arguments: args })) as { content: Array<{ text: string }>; isError?: boolean };
    const text = r.content[0]!.text;
    if (r.isError) return { error: text } as Record<string, any>;
    return JSON.parse(text) as Record<string, any>;
  };
  return { call, close: () => client.close() };
}

let me: Awaited<ReturnType<typeof asUser>>;
const today = new Date().toISOString().slice(0, 10);

beforeAll(async () => {
  await seed();
  me = await asUser('u1', 'Asha');
});
afterAll(async () => me?.close());

const doc = (c: string, id: string) => admin.get(c, id) as Promise<Plain>;
const revisionsFor = async (id: string) => (await admin.where('revisions', 'entityId', id)) as Plain[];

describe('workspaces and accounts', () => {
  it('lists the workspace with its currency, and balances', async () => {
    expect((await me.call('list_workspaces'))[0]).toMatchObject({ id: WS, currency: 'INR', you_own_it: true });
    const a = await me.call('list_accounts');
    expect(a.accounts.find((x: any) => x.id === 'bank').balance).toBe(100000);
  });
});

describe('several workspaces', () => {
  it('asks which one when none is named, and keeps each call to the one named', async () => {
    const set = (collection: string, id: string, data: Plain) => ({ kind: 'set' as const, collection, id, data: { id, ...data } });
    await admin.commit([
      set('workspaces', 'ws2', { name: 'Shop', ownerId: 'm1', baseCurrency: 'INR', fyStartMonth: 4 }),
      set('roles', 'ws2_owner', { workspaceId: 'ws2', name: 'Owner', isSystem: true, permissions: perms(() => true) }),
      set('memberships', 'ws2_m1', { workspaceId: 'ws2', uid: 'm1', roleId: 'ws2_owner', status: 'active' }),
      set('memberships', `${WS}_m1`, { workspaceId: WS, uid: 'm1', roleId: `${WS}_owner`, status: 'active' }),
      set('users', 'm1', { lastWorkspaceId: 'ws2' }),
      set('accounts', 'till', { workspaceId: 'ws2', name: 'Till', type: 'cash', openingBalance: 500 }),
    ]);
    const m = await asUser('m1', 'Mo');
    expect((await m.call('list_workspaces')).map((w: any) => w.id).sort()).toEqual([WS, 'ws2']);
    const refused = await m.call('list_accounts');
    expect(refused.error).toMatch(/2 workspaces\. Ask which one/);
    expect(refused.error).toContain('Shop (ws2)');
    expect((await m.call('list_accounts', { workspace_id: 'ws2' })).accounts.map((a: any) => a.id)).toEqual(['till']);
    const c = await m.call('create_contact', { workspace_id: 'ws2', name: 'Supplier' });
    expect((await doc('contacts', c.id)).workspaceId).toBe('ws2');
    expect((await m.call('get_contact', { workspace_id: WS, contact_id: c.id })).error).toMatch(/No contact/);
    await m.close();
  });
});

describe('contacts', () => {
  let id = '';
  it('creates one the way the app does, with the audit trail', async () => {
    const r = await me.call('create_contact', { name: 'Kabir Mehta', phone: '+91 98200 41733', emails: ['kabir@example.com', ' '] });
    id = r.id;
    const d = await doc('contacts', id);
    expect(d).toMatchObject({
      workspaceId: WS, name: 'Kabir Mehta', type: 'person', relationship: 'external',
      emails: [{ value: 'kabir@example.com', label: 'Other' }], email: 'kabir@example.com',
      createdBy: { uid: 'u1', name: 'Asha' }, updatedBy: { uid: 'u1', name: 'Asha' },
    });
    expect(d.createdAt).toBeInstanceOf(Date);
    const revs = await revisionsFor(id);
    expect(revs).toHaveLength(1);
    expect(revs[0]).toMatchObject({ entityType: 'contacts', action: 'create', by: { uid: 'u1' } });
  });

  it('updates only what is given, and clears with null', async () => {
    await me.call('update_contact', { contact_id: id, notes: 'College friend' });
    await me.call('update_contact', { contact_id: id, phone: null });
    const d = await doc('contacts', id);
    expect(d.notes).toBe('College friend');
    expect('phone' in d).toBe(false);
    expect(d.name).toBe('Kabir Mehta');
  });

  it('a view-only member is refused, readably', async () => {
    const viewer = await asUser('v1', 'Vik');
    const r = await viewer.call('create_contact', { name: 'X' });
    expect(r.error).toMatch(/role in this workspace does not allow you to add contacts/);
    expect((await viewer.call('list_contacts')).contacts.length).toBeGreaterThan(0);
    await viewer.close();
  });
});

describe('categories and budgets', () => {
  it('creates, renames, and will not delete a built-in one', async () => {
    const c = await me.call('create_category', { name: 'Fuel', kind: 'expense' });
    expect(await doc('categories', c.id)).toMatchObject({ name: 'Fuel', kind: 'expense', isSystem: false });
    await me.call('update_category', { category_id: c.id, name: 'Petrol' });
    expect((await doc('categories', c.id)).name).toBe('Petrol');
    expect((await me.call('delete_category', { category_id: 'food' })).error).toMatch(/built-in/);
    expect((await me.call('delete_category', { category_id: c.id })).deleted).toBe(true);
    expect(await admin.get('categories', c.id)).toBeNull();
  });

  it('a budget reports what was spent this month', async () => {
    const b = await me.call('create_budget', { category_id: 'food', amount: 6000, period: 'monthly' });
    await me.call('create_transaction', { account_id: 'bank', date: today, note: 'Lunch', lines: [{ type: 'expense', amount: 450, category_id: 'food' }] });
    const list = await me.call('list_budgets');
    expect(list.budgets.find((x: any) => x.id === b.id)).toMatchObject({ limit: 6000, spent: 450, left: 5550, category: 'Food' });
    expect((await me.call('create_budget', { category_id: 'salary', amount: 1, period: 'monthly' })).error).toMatch(/expense categories/);
    await me.call('update_budget', { budget_id: b.id, amount: 7000 });
    expect((await doc('budgets', b.id)).amount).toBe(7000);
    expect((await me.call('delete_budget', { budget_id: b.id })).deleted).toBe(true);
  });
});

describe('transactions', () => {
  it('an expense is stored exactly as the app stores one', async () => {
    const r = await me.call('create_transaction', {
      account_id: 'bank', date: '2026-11-20', note: 'Fresh Mart',
      lines: [{ type: 'expense', amount: 2796, category_id: 'food' }, { type: 'fee', amount: 578 }],
    });
    const d = await doc('transactions', r.id);
    expect(d).toMatchObject({
      workspaceId: WS, accountId: 'bank', totalAmount: -3374, hasSplit: true, financialYear: '2026-27', note: 'Fresh Mart',
      createdBy: { uid: 'u1', name: 'Asha' },
    });
    expect((d.date as Date).toISOString()).toBe('2026-11-19T18:30:00.000Z'); // midnight IST
    expect(d.lines).toEqual([
      expect.objectContaining({ type: 'expense', amount: 2796, categoryId: 'food' }),
      expect.objectContaining({ type: 'fee', amount: 578 }),
    ]);
    expect((d.lines as Plain[])[0]!.lineId).toMatch(/^l0_\d+$/);
  });

  it('a transfer is stored as the balancing pair, and moves the balances', async () => {
    const before = await me.call('list_accounts');
    const bal = (r: any, id: string) => r.accounts.find((x: any) => x.id === id).balance;
    const r = await me.call('create_transaction', { account_id: 'bank', note: 'Card bill', lines: [{ type: 'transfer', amount: 5000, to_account_id: 'card' }] });
    const d = await doc('transactions', r.id);
    expect(d.totalAmount).toBe(-5000);
    expect((d.lines as Plain[]).map((l) => [l.type, l.amount, l.toAccountId ?? null])).toEqual([
      ['transfer_out', 5000, null],
      ['transfer_in', 5000, 'card'],
    ]);
    const after = await me.call('list_accounts');
    expect(bal(after, 'bank') - bal(before, 'bank')).toBe(-5000);
    expect(bal(after, 'card') - bal(before, 'card')).toBe(5000);
  });

  it('refuses what the app refuses', async () => {
    expect((await me.call('create_transaction', { account_id: 'bank', lines: [{ type: 'expense', amount: 10, category_id: 'salary' }] })).error).toMatch(/income category/);
    expect((await me.call('create_transaction', { account_id: 'bank', lines: [{ type: 'transfer', amount: 10, to_account_id: 'bank' }] })).error).toMatch(/must differ/);
    expect((await me.call('create_transaction', { account_id: 'nope', lines: [{ type: 'income', amount: 10 }] })).error).toMatch(/No account/);
  });

  it('updates rewrite the whole entry as the app does, and deletes go', async () => {
    const r = await me.call('create_transaction', { account_id: 'bank', note: 'Salary', lines: [{ type: 'income', amount: 85000, category_id: 'salary' }] });
    await me.call('update_transaction', { transaction_id: r.id, note: null, lines: [{ type: 'income', amount: 86000, category_id: 'salary' }] });
    const d = await doc('transactions', r.id);
    expect(d.totalAmount).toBe(86000);
    expect('note' in d).toBe(false);
    expect(d.createdBy).toEqual({ uid: 'u1', name: 'Asha' });
    expect((await me.call('delete_transaction', { transaction_id: r.id })).deleted).toBe(true);
    expect((await revisionsFor(r.id)).map((x) => x.action).sort()).toEqual(['create', 'delete', 'update']);
  });
});

describe('debts', () => {
  it('lend 16,000; 15,000 back leaves it open; the last 1,000 settles it', async () => {
    const c = await me.call('create_contact', { name: 'Ravi' });
    const d = await me.call('create_debt', { contact_id: c.id, direction: 'receivable', amount: 16000, account_id: 'bank', label: 'Bike' });
    expect(await doc('debts', d.id)).toMatchObject({ contactId: c.id, direction: 'owed', purpose: 'loan', principal: 16000, status: 'open', label: 'Bike' });
    expect(await doc('transactions', d.opening_transaction_id)).toMatchObject({
      accountId: 'bank', contactId: c.id, totalAmount: -16000, note: 'Opening balance',
      lines: [expect.objectContaining({ type: 'lend', amount: 16000, debtId: d.id, note: 'Opening balance' })],
    });
    const part = await me.call('record_debt_repayment', { debt_id: d.id, amount: 15000, account_id: 'bank' });
    expect(part).toMatchObject({ outstanding_before: 16000, outstanding_now: 1000, debt_settled: false });
    expect((await doc('debts', d.id)).status).toBe('open');
    const rest = await me.call('record_debt_repayment', { debt_id: d.id, amount: 1000, account_id: 'bank' });
    expect(rest.debt_settled).toBe(true);
    expect((await doc('debts', d.id)).status).toBe('settled');
    expect((await me.call('list_debts', { status: 'settled' })).debts.map((x: any) => x.id)).toContain(d.id);
  });

  it('a debt with no account movement is recorded outside your accounts', async () => {
    const c = await me.call('create_contact', { name: 'Meera' });
    const d = await me.call('create_debt', { contact_id: c.id, direction: 'payable', amount: 25000 });
    expect(await doc('transactions', d.opening_transaction_id)).toMatchObject({
      accountId: '__external__', totalAmount: 0, lines: [expect.objectContaining({ type: 'borrow', external: true })],
    });
    await me.call('update_debt', { debt_id: d.id, label: 'Deposit' });
    expect((await doc('debts', d.id)).label).toBe('Deposit');
    expect((await me.call('delete_debt', { debt_id: d.id })).deleted).toBe(true);
  });
});

describe('dues', () => {
  it('part paid, edited, then settled, with payments kept in step', async () => {
    const due = await me.call('create_due', { title: 'School fees', direction: 'payable', amount: 18000, due_date: '2026-12-05', category_id: 'food' });
    expect(await doc('dues', due.id)).toMatchObject({
      direction: 'payable', title: 'School fees', amount: 18000, status: 'open', occurrence: 1, categoryId: 'food',
      lines: [expect.objectContaining({ type: 'expense', amount: 18000, categoryId: 'food' })],
    });
    const p1 = await me.call('record_due_payment', { due_id: due.id, account_id: 'bank', amount: 5000 });
    expect(p1).toMatchObject({ due_status: 'partial', left: 13000 });
    expect(await doc('transactions', p1.transaction_id)).toMatchObject({ dueId: due.id, totalAmount: -5000, note: 'School fees' });

    const up = await me.call('update_due', { due_id: due.id, amount: 20000, title: 'School fees, term 2' });
    expect(up.payments_updated).toBe(1);
    expect(await doc('transactions', p1.transaction_id)).toMatchObject({ totalAmount: -5000, note: 'School fees, term 2' });

    const p2 = await me.call('record_due_payment', { due_id: due.id, account_id: 'bank' });
    expect(p2).toMatchObject({ amount: 15000, due_status: 'settled', left: 0 });
    expect((await doc('dues', due.id)).status).toBe('settled');
    expect((await me.call('list_dues')).dues.map((x: any) => x.id)).not.toContain(due.id);
  });

  it('cancels, reopens and deletes', async () => {
    const due = await me.call('create_due', { title: 'Gym', direction: 'payable', amount: 1500, due_date: today, repeats: 'monthly' });
    await me.call('update_due', { due_id: due.id, status: 'cancelled' });
    expect((await me.call('record_due_payment', { due_id: due.id, account_id: 'bank' })).error).toMatch(/cancelled/);
    expect((await me.call('delete_due', { due_id: due.id })).deleted).toBe(true);
  });
});
