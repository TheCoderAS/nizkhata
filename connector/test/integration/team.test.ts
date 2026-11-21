// Members, roles, invites, workspace settings and the account: read only, against the emulator.

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';

import { Books } from '../../src/books.js';
import { Firestore, type Plain } from '../../src/firestore.js';
import { buildMcpServer } from '../../src/server.js';
import { guardWrites, type Ctx } from '../../src/tools/common.js';
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
  const fs = guardWrites(new Firestore(BASE, idToken(uid)));
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

const WRITE_TOOLS = [
  'invite_member', 'revoke_invite', 'change_member_role', 'remove_member', 'leave_workspace', 'link_member_contact',
  'create_role', 'update_role', 'duplicate_role', 'delete_role', 'create_workspace', 'update_workspace', 'delete_workspace', 'delete_my_account',
];

describe('read only', () => {
  it('lists members, roles and invites, and the account', async () => {
    await admin.commit([
      { kind: 'set', collection: 'invites', id: `${WS}_new@example.com`, data: { id: `${WS}_new@example.com`, workspaceId: WS, email: 'new@example.com', roleId: `${WS}_viewer`, status: 'pending', expiresAt: new Date(Date.now() + 86_400_000) } },
      { kind: 'set', collection: 'users', id: 'o1', data: { uid: 'o1', email: 'o1@example.com', displayName: 'Ola P' } },
    ]);
    const m = await owner.call('list_members', { workspace_id: WS });
    expect(m.members.find((x: any) => x.uid === 'o1')).toMatchObject({ role: 'Owner', is_owner: true, is_you: true });
    expect(m.members.find((x: any) => x.uid === 'v1')).toMatchObject({ role: 'Viewer', is_owner: false });
    const r = await owner.call('list_roles', { workspace_id: WS });
    expect(r.roles.find((x: any) => x.name === 'Viewer').permissions).toContain('members.view');
    expect((await owner.call('list_invites', { workspace_id: WS })).invites[0]).toMatchObject({ email: 'new@example.com', role: 'Viewer', status: 'pending' });
    expect(await owner.call('get_my_account')).toMatchObject({ name: 'Ola P', email: 'o1@example.com', workspaces: [{ id: WS, you_own_it: true }] });
    expect((await owner.call('list_workspaces'))[0]).toMatchObject({ id: WS, currency: 'INR', financial_year_starts_month: 4 });
  });

  it('has no tool that changes members, roles, the workspace or the account', async () => {
    for (const t of WRITE_TOOLS) expect((await owner.call(t, { workspace_id: WS })).error, t).toBeTruthy();
  });

  it('refuses such writes even if a tool tried one', async () => {
    const fs = guardWrites(new Firestore(BASE, idToken('o1')));
    for (const collection of ['workspaces', 'memberships', 'roles', 'invites', 'users', 'devices']) {
      await expect(fs.commit([{ kind: 'update', collection, id: 'x', data: { a: 1 } }])).rejects.toThrow(/can't change/);
    }
    expect(((await admin.get('workspaces', WS)) as Plain).name).toBe('Team');
  });
});
