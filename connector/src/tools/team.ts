// Members, roles, invites and the person's own account: READ ONLY. The
// connector shows them but never changes them. Inviting or removing members,
// editing roles, workspace settings and the person's account stay in the app,
// by the owner's decision: no tool here, or anywhere in the connector, writes
// to memberships, roles, invites, workspaces or users.

import { listWorkspaces } from '../books.js';
import type { Plain } from '../firestore.js';
import { READ, run, workspaceArg, type Register } from './common.js';

/** The permission catalogue (mobile/lib/data/permissions.dart kPermissions), plus the own-records scope. */
export const PERMISSIONS = [
  'transactions.view', 'transactions.create', 'transactions.edit', 'transactions.delete',
  'accounts.view', 'accounts.manage', 'categories.view', 'categories.manage',
  'contacts.view', 'contacts.manage', 'debts.view', 'debts.manage', 'dues.view', 'dues.manage',
  'shared.view', 'shared.manage', 'reports.view', 'reports.export',
  'members.view', 'members.invite', 'members.remove', 'roles.view', 'roles.manage',
  'workspace.edit', 'workspace.delete',
] as const;
const ROLE_KEYS = [...PERMISSIONS, 'scope.own'] as const;

const permList = (p: Record<string, boolean> | undefined) => ROLE_KEYS.filter((k) => p?.[k] === true);

export const registerTeamTools: Register = (server, ctx) => {
  // ---- reading ----
  server.registerTool(
    'list_members',
    {
      title: 'List members',
      description: 'Who is in the workspace, with their role and the contact each is linked to (for own-records roles).',
      inputSchema: workspaceArg,
      annotations: READ,
    },
    ({ workspace_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const [members, roles, contacts] = await Promise.all([b.load('memberships'), b.load('roles'), b.load('contacts').catch(() => [])]);
        const roleName = new Map(roles.map((r) => [String(r.id), String(r.name ?? '')]));
        const contactName = new Map((contacts as Plain[]).map((c) => [String(c.id), String(c.name ?? '')]));
        return {
          members: members.map((m) => ({
            membership_id: m.id,
            uid: m.uid,
            name: m.displayName ?? undefined,
            email: m.email ?? undefined,
            role: roleName.get(String(m.roleId)) ?? m.roleId,
            role_id: m.roleId,
            is_owner: m.uid === b.ws.ownerId,
            is_you: m.uid === b.actor.uid,
            ...(m.linkedContactId ? { linked_contact: contactName.get(String(m.linkedContactId)) ?? m.linkedContactId, linked_contact_id: m.linkedContactId } : {}),
          })),
        };
      }),
  );

  server.registerTool(
    'list_roles',
    {
      title: 'List roles',
      description: 'The workspace roles and what each allows. Built-in (system) roles: Owner, Admin, Editor, Viewer.',
      inputSchema: workspaceArg,
      annotations: READ,
    },
    ({ workspace_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        return {
          roles: (await b.load('roles')).map((r) => ({
            id: r.id,
            name: r.name,
            built_in: r.isSystem === true,
            permissions: permList(r.permissions as Record<string, boolean>),
          })),
          all_permissions: ROLE_KEYS,
        };
      }),
  );

  server.registerTool(
    'list_invites',
    {
      title: 'List invites',
      description: 'Invitations to join this workspace and their state (pending, accepted, revoked).',
      inputSchema: workspaceArg,
      annotations: READ,
    },
    ({ workspace_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const roles = new Map((await b.load('roles')).map((r) => [String(r.id), String(r.name ?? '')]));
        return {
          invites: (await b.load('invites')).map((i) => ({
            id: i.id,
            email: i.email,
            role: roles.get(String(i.roleId)) ?? i.roleId,
            status: i.status,
            ...(i.expiresAt instanceof Date ? { expires: i.expiresAt.toISOString().slice(0, 10) } : {}),
          })),
        };
      }),
  );

  server.registerTool(
    'get_my_account',
    {
      title: 'My account',
      description: 'The signed-in Niz Khata account: name, email, and the workspaces it belongs to. Read only: the account is changed in the app.',
      inputSchema: {},
      annotations: READ,
    },
    () =>
      run(async () => {
        const c = ctx();
        const [profile, workspaces] = await Promise.all([c.fs.get('users', c.actor.uid).catch(() => null), listWorkspaces(c.fs, c.actor.uid)]);
        return {
          name: (profile?.displayName as string | undefined) || c.actor.name,
          email: (profile?.email as string | undefined) || c.email,
          ...(profile?.createdAt instanceof Date ? { member_since: profile.createdAt.toISOString().slice(0, 10) } : {}),
          workspaces: workspaces.map((w) => ({ id: w.id, name: w.name, you_own_it: w.ownerId === c.actor.uid })),
        };
      }),
  );
};
