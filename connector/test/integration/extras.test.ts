// Settle up, statement import, the Reports tabs and deleting an account, against the emulator.

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';

import { Books } from '../../src/books.js';
import { Firestore, type Plain } from '../../src/firestore.js';
import { buildMcpServer } from '../../src/server.js';
import type { Ctx } from '../../src/tools/common.js';
import { PERMISSIONS } from '../../src/tools/team.js';

const PROJECT = process.env.GCLOUD_PROJECT ?? 'rules-test';
const HOST = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
const BASE = `http://${HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;
const TZ = 'Asia/Kolkata';
const WS = 'xw1';

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
const perms = (on: (p: string) => boolean) => Object.fromEntries(PERMISSIONS.map((p) => [p, on(p)]));

async function asUser(uid: string, name: string, extra: Partial<Ctx> = {}) {
  const fs = new Firestore(BASE, idToken(uid));
  const actor = { uid, name };
  const ctx: Ctx = { fs, actor, email: `${uid}@example.com`, timeZone: TZ, books: (w?: string) => Books.open(fs, actor, TZ, w), ...extra };
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

let me: Awaited<ReturnType<typeof asUser>>;
const set = (collection: string, id: string, data: Plain) => ({ kind: 'set' as const, collection, id, data: { id, ...data } });

beforeAll(async () => {
  await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  await admin.commit([
    set('workspaces', WS, { name: 'Home', ownerId: 'x1', baseCurrency: 'INR', fyStartMonth: 4 }),
    set('roles', `${WS}_owner`, { workspaceId: WS, name: 'Owner', isSystem: true, permissions: perms(() => true) }),
    set('memberships', `${WS}_x1`, { workspaceId: WS, uid: 'x1', roleId: `${WS}_owner`, status: 'active' }),
    set('accounts', 'bank', { workspaceId: WS, name: 'Bank', type: 'bank', openingBalance: 10000 }),
    set('categories', 'food', { workspaceId: WS, name: 'Food', kind: 'expense', isSystem: true }),
    set('categories', 'other', { workspaceId: WS, name: 'Other Expense', kind: 'expense', isSystem: true }),
    set('categories', 'salary', { workspaceId: WS, name: 'Salary', kind: 'income', isSystem: true }),
    set('contacts', 'ravi', { workspaceId: WS, name: 'Ravi' }),
  ]);
  me = await asUser('x1', 'Xen');
});
afterAll(async () => me?.close());

const today = new Date().toISOString().slice(0, 10);

describe('settle up', () => {
  it('nets every open debt with a contact into one transaction', async () => {
    const lent = await me.call('create_debt', { contact_id: 'ravi', direction: 'receivable', amount: 1000, account_id: 'bank', date: today });
    const borrowed = await me.call('create_debt', { contact_id: 'ravi', direction: 'payable', amount: 300, account_id: 'bank', date: today });
    expect(lent.error ?? borrowed.error).toBeUndefined();
    const plan = await me.call('settle_up', { contact_id: 'ravi', account_id: 'bank', confirm: false });
    expect(plan).toMatchObject({ preview: true, net: 700 });
    expect(plan.debts).toHaveLength(2);
    const done = await me.call('settle_up', { contact_id: 'ravi', account_id: 'bank', confirm: true });
    const t = (await admin.get('transactions', done.transaction_id)) as Plain;
    expect(t).toMatchObject({ totalAmount: 700, note: 'Settle-up with Ravi', contactId: 'ravi', hasSplit: true });
    expect((t.lines as Plain[]).every((l) => l.type === 'repayment' && l.note === 'Settle-up')).toBe(true);
    const debts = (await me.call('list_debts')).debts.filter((d: any) => d.contact === 'Ravi' || d.contact_id === 'ravi');
    expect(debts.every((d: any) => d.outstanding === 0)).toBe(true);
    expect((await me.call('settle_up', { contact_id: 'ravi', account_id: 'bank', confirm: false })).error).toMatch(/Nothing is open/);
  });
});

describe('statement import', () => {
  it('learns categories, matches a due, skips duplicates, and stores the import key', async () => {
    await me.call('create_transaction', { account_id: 'bank', date: '2026-10-02', note: 'UPI SWIGGY ORDER 123', lines: [{ type: 'expense', amount: 250, category_id: 'food' }] });
    const due = await me.call('create_due', { account_id: 'bank', title: 'Rent', due_date: '2026-11-05', lines: [{ type: 'expense', amount: 15000, category_id: 'other' }] });
    expect(due.error).toBeUndefined();
    const rows = [
      { date: '2026-10-02', amount: -250, description: 'UPI SWIGGY ORDER 123' }, // already there
      { date: '2026-11-03', amount: -412.5, description: 'UPI-SWIGGY BLR' }, // learned: Food
      { date: '2026-11-04', amount: -15000, description: 'NEFT LANDLORD' }, // the rent due
      { date: '2026-11-06', amount: 50000, description: 'SALARY NOV', category_id: 'salary' },
      { date: '2026-11-07', amount: -99, description: 'MISC' }, // default category
    ];
    const dry = await me.call('import_transactions', { account_id: 'bank', rows, default_expense_category_id: 'other', dry_run: true });
    expect(dry).toMatchObject({ rows: 5, to_import: 4, duplicates_skipped: 1, due_payments: 1 });
    expect(dry.detail[1]).toMatchObject({ category: 'Food', learned: true });
    expect(dry.detail[2]).toMatchObject({ pays_due: 'Rent' });
    expect(dry.detail[4]).toMatchObject({ category: 'Other Expense' });

    const real = await me.call('import_transactions', { account_id: 'bank', rows, default_expense_category_id: 'other', dry_run: false });
    expect(real.imported).toBe(true);
    const all = (await admin.where('transactions', 'workspaceId', WS)) as Plain[];
    const swiggy = all.find((t) => t.note === 'UPI-SWIGGY BLR')!;
    expect(swiggy).toMatchObject({ totalAmount: -412.5, importKey: 'bank|2026-11-03|-412.50|upiswiggyblr' });
    expect((swiggy.lines as Plain[])[0]).toMatchObject({ type: 'expense', amount: 412.5, categoryId: 'food' });
    const rent = all.find((t) => t.dueId === due.id)!;
    expect(rent.totalAmount).toBe(-15000);
    expect(((await admin.get('dues', due.id)) as Plain).status).toBe('settled');

    const again = await me.call('import_transactions', { account_id: 'bank', rows, dry_run: true });
    expect(again).toMatchObject({ to_import: 0, duplicates_skipped: 5 });
  });
});

describe('reports', () => {
  it('sums taxable lines by head, with TDS and contacts for INR', async () => {
    await me.call('create_transaction', {
      account_id: 'bank', date: '2026-11-10', contact_id: 'ravi', note: 'Consulting',
      lines: [{ type: 'income', amount: 9000, category_id: 'salary', tax: { taxable: true, head: 'professional_fees', tds_amount: 900 } }],
    });
    const r = await me.call('get_tax_summary', { fy: '2026-27' });
    expect(r).toMatchObject({ fy: '2026-27', total_taxable: 9000, total_tds: 900 });
    expect(r.by_head[0]).toMatchObject({ head: 'professional_fees', label: 'Professional fees', taxable: 9000, tds: 900, lines: 1 });
    expect(r.by_contact[0]).toMatchObject({ contact: 'Ravi', tds: 900 });
    expect(r.lines[0]).toMatchObject({ description: 'Consulting', taxable: 9000 });
    expect((await me.call('get_tax_summary', { fy: '2025-26' })).total_taxable).toBe(0);
  });

  it('draws net worth month by month', async () => {
    const r = await me.call('get_net_worth', { fy: '2026-27' });
    expect(r.months[0].month).toBe('2026-04');
    const nov = r.months.find((m: any) => m.month === '2026-11');
    // Opening 10000 - 250 - 412.5 - 15000 + 50000 - 99 + 9000 (+700 settle - 1000 lent + 300 borrowed, all netting out with debts)
    const bal = (await me.call('list_accounts')).accounts.find((a: any) => a.id === 'bank').balance;
    expect(nov.accounts).toBe(bal);
    expect(nov.net_worth).toBe(bal);
  });

  it('totals money with each contact', async () => {
    const r = await me.call('get_contact_report', { fy: '2026-27' });
    expect(r.contacts.find((c: any) => c.contact === 'Ravi')).toMatchObject({ received: expect.any(Number), paid: expect.any(Number) });
  });
});

describe('delete my account', () => {
  it('needs a fresh sign-in, then erases what they own and leaves what they joined', async () => {
    await admin.commit([
      set('workspaces', 'other', { name: 'Theirs', ownerId: 'y1', baseCurrency: 'INR', fyStartMonth: 4 }),
      set('roles', 'other_owner', { workspaceId: 'other', name: 'Owner', isSystem: true, permissions: perms(() => true) }),
      set('memberships', 'other_y1', { workspaceId: 'other', uid: 'y1', roleId: 'other_owner', status: 'active' }),
      set('memberships', 'other_z1', { workspaceId: 'other', uid: 'z1', roleId: 'other_owner', status: 'active' }),
      set('users', 'z1', { uid: 'z1' }),
    ]);
    const stale = await asUser('z1', 'Zed', { authTime: Math.floor(Date.now() / 1000) - 3600, deleteSignIn: async () => {} });
    expect((await stale.call('delete_my_account', { confirm: 'DELETE' })).error).toMatch(/fresh sign-in/);
    await stale.close();

    let signInDeleted = false;
    const z = await asUser('z1', 'Zed', { authTime: Math.floor(Date.now() / 1000), deleteSignIn: async () => { signInDeleted = true; } });
    const ws = await z.call('create_workspace', { name: 'Zed Books', currency: 'INR' });
    await z.call('create_account', { workspace_id: ws.id, name: 'Cash', type: 'cash' });
    expect((await z.call('delete_my_account', { confirm: 'nope' })).error).toBeTruthy();
    const r = await z.call('delete_my_account', { confirm: 'DELETE' });
    expect(r).toMatchObject({ deleted: true, workspaces_deleted: 1, workspaces_left: 1 });
    expect(signInDeleted).toBe(true);
    expect(await admin.get('workspaces', ws.id)).toBeNull();
    expect(await admin.where('accounts', 'workspaceId', ws.id)).toHaveLength(0);
    expect(await admin.get('memberships', 'other_z1')).toBeNull();
    expect(await admin.get('workspaces', 'other')).not.toBeNull();
    expect(await admin.get('users', 'z1')).toBeNull();
    await z.close();
  });
});
