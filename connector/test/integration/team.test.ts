// Members, roles, invites and workspaces, against the emulator and the real rules.

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
const WS = 'tw1';

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

let owner: Awaited<ReturnType<typeof asUser>>;
let viewer: Awaited<ReturnType<typeof asUser>>;

beforeAll(async () => {
  await fetch(`http://${HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  const set = (collection: string, id: string, data: Plain) => ({ kind: 'set' as const, collection, id, data: { id, ...data } });
  await admin.commit([
    set('workspaces', WS, { name: 'Team', ownerId: 'o1', baseCurrency: 'INR', fyStartMonth: 4 }),
    set('roles', `${WS}_owner`, { workspaceId: WS, name: 'Owner', isSystem: true, permissions: perms(() => true) }),
    set('roles', `${WS}_viewer`, { workspaceId: WS, name: 'Viewer', isSystem: true, permissions: perms((p) => p.endsWith('.view')) }),
    set('memberships', `${WS}_o1`, { workspaceId: WS, uid: 'o1', roleId: `${WS}_owner`, status: 'active', displayName: 'Ola' }),
    set('memberships', `${WS}_v1`, { workspaceId: WS, uid: 'v1', roleId: `${WS}_viewer`, status: 'active', displayName: 'Vik' }),
    set('contacts', 'cv', { workspaceId: WS, name: 'Vik' }),
  ]);
  owner = await asUser('o1', 'Ola');
  viewer = await asUser('v1', 'Vik');
});
afterAll(async () => {
  await owner?.close();
  await viewer?.close();
});

describe('members', () => {
  it('lists members with roles', async () => {
    const r = await owner.call('list_members', { workspace_id: WS });
    expect(r.members.find((m: any) => m.uid === 'o1')).toMatchObject({ role: 'Owner', is_owner: true, is_you: true });
    expect(r.members.find((m: any) => m.uid === 'v1')).toMatchObject({ role: 'Viewer', is_owner: false });
  });

  it('invites by email as the app does, and refuses the Owner role', async () => {
    expect((await owner.call('invite_member', { workspace_id: WS, email: 'x@y.com', role_id: `${WS}_owner` })).error).toMatch(/Owner role/);
    const r = await owner.call('invite_member', { workspace_id: WS, email: 'New@Example.com', role_id: `${WS}_viewer` });
    expect(r.id).toBe(`${WS}_new@example.com`);
    const inv = (await admin.get('invites', r.id)) as Plain;
    expect(inv).toMatchObject({ email: 'new@example.com', status: 'pending', invitedBy: 'o1', roleId: `${WS}_viewer` });
    expect((await owner.call('list_invites', { workspace_id: WS })).invites[0]).toMatchObject({ status: 'pending', role: 'Viewer' });
    await owner.call('revoke_invite', { workspace_id: WS, invite_id: r.id });
    expect(((await admin.get('invites', r.id)) as Plain).status).toBe('revoked');
  });

  it('a viewer cannot invite', async () => {
    expect((await viewer.call('invite_member', { workspace_id: WS, email: 'z@y.com', role_id: `${WS}_viewer` })).error).toBeTruthy();
  });

  it("links a member's own contact, and an owner's role can't change", async () => {
    await viewer.call('link_member_contact', { workspace_id: WS, membership_id: `${WS}_v1`, contact_id: 'cv' });
    expect(((await admin.get('memberships', `${WS}_v1`)) as Plain).linkedContactId).toBe('cv');
    expect((await owner.call('change_member_role', { workspace_id: WS, membership_id: `${WS}_o1`, role_id: `${WS}_viewer` })).error).toMatch(/owner's role/);
  });
});

describe('roles', () => {
  it('creates, updates, duplicates and deletes a role with the guards', async () => {
    const c = await owner.call('create_role', { workspace_id: WS, name: 'Bookkeeper', permissions: ['transactions.view', 'transactions.create'] });
    const stored = (await admin.get('roles', c.id)) as Plain;
    expect(stored).toMatchObject({ isSystem: false, name: 'Bookkeeper' });
    expect((stored.permissions as Plain)['transactions.create']).toBe(true);
    expect((stored.permissions as Plain)['transactions.delete']).toBe(false);

    await owner.call('update_role', { workspace_id: WS, role_id: c.id, permissions: ['transactions.view'] });
    expect((((await admin.get('roles', c.id)) as Plain).permissions as Plain)['transactions.create']).toBe(false);
    expect((await owner.call('update_role', { workspace_id: WS, role_id: `${WS}_viewer`, name: 'Watcher' })).error).toMatch(/built-in/);

    const d = await owner.call('duplicate_role', { workspace_id: WS, role_id: `${WS}_viewer` });
    expect(d.name).toBe('Viewer (copy)');
    expect((await owner.call('delete_role', { workspace_id: WS, role_id: `${WS}_viewer` })).error).toMatch(/Built-in/);

    await owner.call('change_member_role', { workspace_id: WS, membership_id: `${WS}_v1`, role_id: c.id });
    expect((await owner.call('delete_role', { workspace_id: WS, role_id: c.id })).error).toMatch(/assigned/);
    await owner.call('change_member_role', { workspace_id: WS, membership_id: `${WS}_v1`, role_id: `${WS}_viewer` });
    expect((await owner.call('delete_role', { workspace_id: WS, role_id: c.id })).deleted).toBe(true);
    const roles = (await owner.call('list_roles', { workspace_id: WS })).roles.map((r: any) => r.name);
    expect(roles).toContain('Viewer (copy)');
    expect(roles).not.toContain('Bookkeeper');
  });
});

describe('workspaces', () => {
  it('creates a workspace like the app, then renames, then deletes it', async () => {
    const r = await viewer.call('create_workspace', { name: 'Vik Home', currency: 'AUD', time_zone: 'Australia/Sydney' });
    expect(r).toMatchObject({ created: true, fy_start_month: 7, workspaces_now: 2 });
    const ws = (await admin.get('workspaces', r.id)) as Plain;
    expect(ws).toMatchObject({ ownerId: 'v1', baseCurrency: 'AUD', timeZone: 'Australia/Sydney' });
    expect((await admin.where('roles', 'workspaceId', r.id)).map((x) => x.name).sort()).toEqual(['Admin', 'Editor', 'Owner', 'Viewer']);
    expect(await admin.where('categories', 'workspaceId', r.id)).toHaveLength(18);
    expect((await admin.get('memberships', `${r.id}_v1`)) as Plain).toMatchObject({ status: 'active', uid: 'v1' });

    // Works in it as the owner straight away.
    const acct = await viewer.call('create_account', { workspace_id: r.id, name: 'Wallet', type: 'cash' });
    expect(acct.error).toBeUndefined();

    await viewer.call('update_workspace', { workspace_id: r.id, name: 'Vik Sydney', fy_start_month: 1 });
    expect((await admin.get('workspaces', r.id)) as Plain).toMatchObject({ name: 'Vik Sydney', fyStartMonth: 1 });

    expect((await viewer.call('delete_workspace', { workspace_id: r.id, confirm_name: 'nope' })).error).toMatch(/exactly/);
    const del = await viewer.call('delete_workspace', { workspace_id: r.id, confirm_name: 'Vik Sydney' });
    expect(del.deleted).toBe(true);
    expect(await admin.get('workspaces', r.id)).toBeNull();
    expect(await admin.where('categories', 'workspaceId', r.id)).toHaveLength(0);
    expect(await admin.where('accounts', 'workspaceId', r.id)).toHaveLength(0);
    expect(await admin.get('memberships', `${r.id}_v1`)).toBeNull();
  });

  it('a member who is not the owner cannot delete, but can leave; the owner cannot leave', async () => {
    expect((await viewer.call('delete_workspace', { workspace_id: WS, confirm_name: 'Team' })).error).toMatch(/Only the owner/);
    expect((await owner.call('leave_workspace', { workspace_id: WS })).error).toMatch(/owner can't leave/);
    expect((await viewer.call('leave_workspace', { workspace_id: WS })).left).toBe(true);
    expect(await admin.get('memberships', `${WS}_v1`)).toBeNull();
  });
});
