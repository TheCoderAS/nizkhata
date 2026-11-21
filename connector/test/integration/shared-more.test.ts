// The shared ledger's invites and what the creator can do after a rejection, against the emulator.

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

let a: Awaited<ReturnType<typeof asUser>>;
let b: Awaited<ReturnType<typeof asUser>>;

beforeAll(async () => {
  await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  const set = (collection: string, id: string, data: Plain) => ({ kind: 'set' as const, collection, id, data: { id, ...data } });
  const books = (ws: string, uid: string) => [
    set('workspaces', ws, { name: `Books ${uid}`, ownerId: uid, baseCurrency: 'INR', fyStartMonth: 4 }),
    set('roles', `${ws}_owner`, { workspaceId: ws, name: 'Owner', isSystem: true, permissions: perms(() => true) }),
    set('memberships', `${ws}_${uid}`, { workspaceId: ws, uid, roleId: `${ws}_owner`, status: 'active' }),
    set('accounts', `${ws}_bank`, { workspaceId: ws, name: 'Bank', type: 'bank', openingBalance: 10000 }),
    set('categories', `${ws}_food`, { workspaceId: ws, name: 'Food', kind: 'expense', isSystem: true }),
  ];
  await admin.commit([...books('sa', 'ua'), ...books('sb', 'ub')]);
  a = await asUser('ua', 'Asha');
  b = await asUser('ub', 'Bina');
});
afterAll(async () => {
  await a?.close();
  await b?.close();
});

const reflection = async (entryId: string) => (await admin.where('transactions', 'sharedEntryId', entryId))[0] as Plain | undefined;

async function expenseRejected(description: string) {
  const r = await a.call('add_shared_expense', { description, amount: 1000, account_id: 'sa_bank', partners: [{ partner: 'Bina' }] });
  const entry = r.entries[0].entry_id as string;
  expect((await b.call('respond_shared_entry', { entry_id: entry, accept: false })).rejected).toBe(true);
  return entry;
}

describe('invites', () => {
  it('invites by email, the invitee connects, and an invite can be revoked', async () => {
    const inv = await a.call('invite_shared_partner', { email: 'UB@example.com' });
    expect(inv.id).toBe('ua_ub@example.com');
    expect((await b.call('list_share_invites')).received[0]).toMatchObject({ status: 'pending', from: 'Asha' });
    expect((await b.call('accept_share_invites')).connected_with).toEqual(['Asha']);
    expect((await admin.get('sharedConnections', 'ua_ub')) as Plain).toMatchObject({ status: 'active', uids: ['ua', 'ub'] });
    expect(((await admin.get('shareInvites', inv.id)) as Plain).status).toBe('accepted');
    expect((await a.call('list_shared')).partners[0]).toMatchObject({ partner_id: 'ub', name: 'Bina' });

    const other = await a.call('invite_shared_partner', { email: 'cy@example.com' });
    await a.call('revoke_share_invite', { invite_id: other.id });
    expect(((await admin.get('shareInvites', other.id)) as Plain).status).toBe('revoked');
    expect((await b.call('revoke_share_invite', { invite_id: other.id })).error).toMatch(/No invite/);
  });
});

describe('after a rejection', () => {
  it('re-bills, then absorbs into an own expense', async () => {
    const first = await expenseRejected('Dinner');
    const re = await a.call('rebill_shared_entry', { entry_id: first });
    expect(((await admin.get('sharedEntries', first)) as Plain).resolved).toBe(true);
    expect(((await admin.get('sharedEntries', re.new_entry_id)) as Plain)).toMatchObject({ status: 'pending', amount: 500 });
    expect((await reflection(re.new_entry_id))).toBeTruthy();
    expect((await b.call('respond_shared_entry', { entry_id: re.new_entry_id, accept: false })).rejected).toBe(true);

    expect((await b.call('resolve_shared_conflict', { entry_id: re.new_entry_id, mode: 'absorb' })).error).toMatch(/Only the person/);
    expect((await a.call('resolve_shared_conflict', { entry_id: re.new_entry_id, mode: 'absorb' })).resolved).toBe(true);
    const t = (await reflection(re.new_entry_id))!;
    expect(t).toMatchObject({ totalAmount: -500, note: 'Dinner (absorbed)', accountId: 'sa_bank' });
    expect((t.lines as Plain[])[0]).toMatchObject({ type: 'expense', amount: 500, categoryId: 'sa_food' });
    expect((await a.call('list_shared')).entries.some((e: any) => e.conflict)).toBe(false);
  });

  it('removes a rejected expense from the books', async () => {
    const entry = await expenseRejected('Taxi');
    expect(await reflection(entry)).toBeTruthy();
    await a.call('resolve_shared_conflict', { entry_id: entry, mode: 'remove' });
    expect(await reflection(entry)).toBeUndefined();
    expect(((await admin.get('sharedEntries', entry)) as Plain).resolved).toBe(true);
  });

  it('withdraws an entry with its transaction', async () => {
    const r = await a.call('add_shared_expense', { description: 'Tickets', amount: 600, account_id: 'sa_bank', partners: [{ partner: 'Bina' }] });
    const entry = r.entries[0].entry_id as string;
    expect((await b.call('withdraw_shared_entry', { entry_id: entry })).error).toMatch(/Only the person/);
    expect((await a.call('withdraw_shared_entry', { entry_id: entry })).withdrawn).toBe(true);
    expect(await admin.get('sharedEntries', entry)).toBeNull();
    expect(await reflection(entry)).toBeUndefined();
  });
});
