// Members, roles, invites and the workspace itself: everything the app's
// Members, Roles and Workspace settings screens do (mobile/lib/data/mutations.dart,
// state/auth_controller.dart createPersonalWorkspace, services/account_eraser.dart).
// The app's guard rails are kept word for word; the security rules decide the
// rest by the person's role, as they do in the app.

import { z } from 'zod';

import { DEFAULT_TIME_ZONE, UserError, explain, listWorkspaces, type Books } from '../books.js';
import { DELETE as DELETE_FIELD, FirestoreError, newDocId, SERVER_TIME, type Plain, type Write } from '../firestore.js';
import { DESTRUCTIVE, OVERWRITE, READ, WRITE, run, workspaceArg, type Ctx, type Register } from './common.js';

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

const all = (v: boolean) => Object.fromEntries(PERMISSIONS.map((p) => [p, v])) as Record<string, boolean>;
const views = PERMISSIONS.filter((p) => p.endsWith('.view'));
const only = (keys: readonly string[]) => Object.fromEntries(keys.map((k) => [k, true])) as Record<string, boolean>;

/** systemRoleTemplates(), in kSystemRoleOrder. */
const SYSTEM_ROLES: Array<[string, Record<string, boolean>]> = [
  ['Owner', all(true)],
  ['Admin', { ...all(true), 'workspace.delete': false }],
  [
    'Editor',
    only([...views, 'transactions.create', 'transactions.edit', 'transactions.delete', 'accounts.manage', 'categories.manage',
      'contacts.manage', 'debts.manage', 'dues.manage', 'shared.manage', 'reports.export']),
  ],
  ['Viewer', only(views)],
];

/** kDefaultCategories. */
const DEFAULT_CATEGORIES: Array<[string, 'income' | 'expense']> = [
  ['Salary', 'income'], ['Bonus', 'income'], ['Interest (CASA/FD)', 'income'], ['Gift', 'income'],
  ['Reimbursement', 'income'], ['Refund', 'income'], ['Other Income', 'income'],
  ['Food', 'expense'], ['Transport', 'expense'], ['Rent', 'expense'], ['Utilities', 'expense'], ['Shopping', 'expense'],
  ['Health', 'expense'], ['Entertainment', 'expense'], ['Loan Interest', 'expense'], ['Bank Charges', 'expense'],
  ['Taxes & GST', 'expense'], ['Other Expense', 'expense'],
];

/** The currencies the app offers, with each one's usual financial year start (else January). */
const CURRENCIES = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SAR', 'QAR', 'KWD', 'BHD', 'OMR', 'SGD', 'AUD', 'NZD', 'CAD', 'CHF', 'JPY',
  'CNY', 'HKD', 'KRW', 'MYR', 'THB', 'IDR', 'PHP', 'PKR', 'BDT', 'NPR', 'LKR', 'ZAR', 'NGN', 'KES', 'BRL', 'MXN'] as const;
const FY_START: Record<string, number> = { INR: 4, GBP: 4, KWD: 4, AUD: 7, NZD: 4, JPY: 4, HKD: 4, PKR: 7, BDT: 7, NPR: 7, ZAR: 3, KES: 7 };

const permList = (p: Record<string, boolean> | undefined) => ROLE_KEYS.filter((k) => p?.[k] === true);

async function roleOf(b: Books, roleId: string): Promise<Plain> {
  return b.getOne('roles', roleId);
}

function isOwnerRole(r: Plain) {
  return r.isSystem === true && r.name === 'Owner';
}

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

  // ---- members ----
  server.registerTool(
    'invite_member',
    {
      title: 'Invite a member',
      description: 'Invite someone by email to join the workspace with a role (from list_roles). The Owner role cannot be given.',
      inputSchema: { ...workspaceArg, email: z.string().email(), role_id: z.string() },
      annotations: WRITE,
    },
    ({ workspace_id, email, role_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const role = await roleOf(b, role_id);
        if (isOwnerRole(role)) throw new UserError("The Owner role is reserved for the workspace owner and can't be assigned.");
        const mail = email.trim().toLowerCase();
        const id = `${b.ws.id}_${mail}`;
        await b.commit(
          [
            {
              kind: 'set',
              collection: 'invites',
              id,
              data: {
                id, workspaceId: b.ws.id, email: mail, roleId: role_id, status: 'pending', invitedBy: b.actor.uid,
                createdAt: SERVER_TIME, expiresAt: new Date(Date.now() + 14 * 86_400_000),
              },
            },
          ],
          'invite members',
        );
        return { invited: true, id, email: mail, role: role.name, expires_in_days: 14 };
      }),
  );

  server.registerTool(
    'revoke_invite',
    {
      title: 'Revoke an invite',
      description: 'Withdraw a pending invitation.',
      inputSchema: { ...workspaceArg, invite_id: z.string() },
      annotations: OVERWRITE,
    },
    ({ workspace_id, invite_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        await b.getOne('invites', invite_id);
        await b.commit([{ kind: 'update', collection: 'invites', id: invite_id, data: { status: 'revoked' } }], 'manage invites');
        return { revoked: true, id: invite_id };
      }),
  );

  server.registerTool(
    'change_member_role',
    {
      title: "Change a member's role",
      description: "Give a member another role. The owner's role can't be changed, and the Owner role can't be given.",
      inputSchema: { ...workspaceArg, membership_id: z.string(), role_id: z.string() },
      annotations: OVERWRITE,
    },
    ({ workspace_id, membership_id, role_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const m = await b.getOne('memberships', membership_id);
        if (m.uid === b.ws.ownerId) throw new UserError("The workspace owner's role can't be changed.");
        const role = await roleOf(b, role_id);
        if (isOwnerRole(role)) throw new UserError("The Owner role is reserved for the workspace owner and can't be assigned.");
        await b.commit([{ kind: 'update', collection: 'memberships', id: membership_id, data: { roleId: role_id } }], 'change roles');
        return { updated: true, membership_id, role: role.name };
      }),
  );

  server.registerTool(
    'remove_member',
    {
      title: 'Remove a member',
      description: 'Take someone out of the workspace. The owner cannot be removed.',
      inputSchema: { ...workspaceArg, membership_id: z.string() },
      annotations: DESTRUCTIVE,
    },
    ({ workspace_id, membership_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const m = await b.getOne('memberships', membership_id);
        if (m.uid === b.ws.ownerId) throw new UserError("The workspace owner can't be removed.");
        await b.commit([{ kind: 'delete', collection: 'memberships', id: membership_id }], 'remove members');
        return { removed: true, membership_id, name: m.displayName ?? m.email };
      }),
  );

  server.registerTool(
    'leave_workspace',
    {
      title: 'Leave a workspace',
      description: "Leave a workspace someone else owns. The owner can't leave; they delete the workspace instead.",
      inputSchema: { workspace_id: z.string() },
      annotations: DESTRUCTIVE,
    },
    ({ workspace_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        if (b.actor.uid === b.ws.ownerId) throw new UserError("The owner can't leave their own workspace; delete it instead.");
        await b.commit([{ kind: 'delete', collection: 'memberships', id: `${b.ws.id}_${b.actor.uid}` }], 'leave the workspace');
        return { left: true, workspace: b.ws.name };
      }),
  );

  server.registerTool(
    'link_member_contact',
    {
      title: 'Link a member to a contact',
      description:
        "Say which contact stands for a member, so a role limited to own records shows them their own entries. null clears it. Anyone may set their own; others' need members.invite.",
      inputSchema: { ...workspaceArg, membership_id: z.string(), contact_id: z.string().nullable() },
      annotations: OVERWRITE,
    },
    ({ workspace_id, membership_id, contact_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        await b.getOne('memberships', membership_id);
        if (contact_id) await b.getOne('contacts', contact_id);
        await b.commit(
          [{ kind: 'update', collection: 'memberships', id: membership_id, data: { linkedContactId: contact_id ?? DELETE_FIELD } }],
          'link members to contacts',
        );
        return { updated: true, membership_id, linked_contact_id: contact_id };
      }),
  );

  // ---- roles ----
  const permsInput = z.array(z.enum(ROLE_KEYS)).describe('The permissions this role grants; anything not listed is off. "scope.own" limits it to records of the member\'s linked contact.');

  server.registerTool(
    'create_role',
    {
      title: 'Create a role',
      description: 'A custom role with chosen permissions.',
      inputSchema: { ...workspaceArg, name: z.string().min(1), permissions: permsInput },
      annotations: WRITE,
    },
    ({ workspace_id, name, permissions }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const id = newDocId();
        const perms = Object.fromEntries(ROLE_KEYS.map((k) => [k, permissions.includes(k)]));
        await b.commit(
          [{ kind: 'set', collection: 'roles', id, data: { id, workspaceId: b.ws.id, name: name.trim(), isSystem: false, permissions: perms, createdAt: SERVER_TIME } }],
          'manage roles',
        );
        return { created: true, id, name: name.trim(), permissions };
      }),
  );

  server.registerTool(
    'update_role',
    {
      title: 'Update a role',
      description: "Rename a role or set its permissions (the whole list). A built-in role's name can't change.",
      inputSchema: { ...workspaceArg, role_id: z.string(), name: z.string().min(1).optional(), permissions: permsInput.optional() },
      annotations: OVERWRITE,
    },
    ({ workspace_id, role_id, name, permissions }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const r = await roleOf(b, role_id);
        const data: Plain = {};
        if (name !== undefined) {
          if (r.isSystem === true && name.trim() !== r.name) throw new UserError("A built-in role's name can't be changed; duplicate it to customise.");
          data.name = name.trim();
        }
        if (permissions !== undefined) data.permissions = Object.fromEntries(ROLE_KEYS.map((k) => [k, permissions.includes(k)]));
        if (!Object.keys(data).length) throw new UserError('Nothing to change.');
        await b.commit([{ kind: 'update', collection: 'roles', id: role_id, data }], 'manage roles');
        return { updated: true, id: role_id };
      }),
  );

  server.registerTool(
    'duplicate_role',
    {
      title: 'Duplicate a role',
      description: 'Copy a role, built-in or custom, as "<name> (copy)" to customise.',
      inputSchema: { ...workspaceArg, role_id: z.string() },
      annotations: WRITE,
    },
    ({ workspace_id, role_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const r = await roleOf(b, role_id);
        const id = newDocId();
        const name = `${r.name} (copy)`;
        await b.commit(
          [{ kind: 'set', collection: 'roles', id, data: { id, workspaceId: b.ws.id, name, isSystem: false, permissions: { ...(r.permissions as Plain) }, createdAt: SERVER_TIME } }],
          'manage roles',
        );
        return { created: true, id, name };
      }),
  );

  server.registerTool(
    'delete_role',
    {
      title: 'Delete a role',
      description: "Delete a custom role. Built-in roles can't be deleted, nor a role someone still has.",
      inputSchema: { ...workspaceArg, role_id: z.string() },
      annotations: DESTRUCTIVE,
    },
    ({ workspace_id, role_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const r = await roleOf(b, role_id);
        if (r.isSystem === true) throw new UserError("Built-in roles can't be deleted; duplicate one to customise it.");
        if ((await b.load('memberships')).some((m) => m.roleId === role_id)) {
          throw new UserError('This role is assigned to a member; reassign them first.');
        }
        await b.commit([{ kind: 'delete', collection: 'roles', id: role_id }], 'manage roles');
        return { deleted: true, id: role_id, name: r.name };
      }),
  );

  // ---- the workspace ----
  server.registerTool(
    'update_workspace',
    {
      title: 'Update the workspace',
      description: 'Rename it or change the month its financial year starts. Its currency and time zone are fixed for good.',
      inputSchema: { ...workspaceArg, name: z.string().min(1).optional(), fy_start_month: z.number().int().min(1).max(12).optional() },
      annotations: OVERWRITE,
    },
    ({ workspace_id, name, fy_start_month }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const data: Plain = {};
        if (name !== undefined) data.name = name.trim();
        if (fy_start_month !== undefined) data.fyStartMonth = fy_start_month;
        if (!Object.keys(data).length) throw new UserError('Nothing to change.');
        await b.commit([{ kind: 'update', collection: 'workspaces', id: b.ws.id, data }], 'edit the workspace');
        return { updated: true, id: b.ws.id, ...data };
      }),
  );

  server.registerTool(
    'create_workspace',
    {
      title: 'Create a workspace',
      description:
        'A new set of books you own, with its built-in roles and default categories, as the app makes it. Its currency and time zone are fixed for good, so ask the person which they want.',
      inputSchema: {
        name: z.string().min(1),
        currency: z.enum(CURRENCIES),
        time_zone: z.string().optional().describe('IANA time zone, e.g. Asia/Kolkata (the default) or Asia/Bangkok'),
      },
      annotations: WRITE,
    },
    ({ name, currency, time_zone }) =>
      run(async () => {
        const c = ctx();
        const tz = time_zone?.trim() || DEFAULT_TIME_ZONE;
        try {
          new Intl.DateTimeFormat('en-US', { timeZone: tz });
        } catch {
          throw new UserError(`"${tz}" is not a time zone. Use a name like Asia/Kolkata.`);
        }
        return createWorkspace(c, name.trim(), currency, tz);
      }),
  );

  server.registerTool(
    'delete_workspace',
    {
      title: 'Delete a workspace',
      description:
        'Permanently delete a workspace you own and everything in it, for every member. It cannot be undone. confirm_name must be the workspace name exactly.',
      inputSchema: { workspace_id: z.string(), confirm_name: z.string() },
      annotations: DESTRUCTIVE,
    },
    ({ workspace_id, confirm_name }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        if (b.ws.ownerId !== b.actor.uid) throw new UserError('Only the owner can delete a workspace.');
        if (confirm_name.trim() !== b.ws.name.trim()) throw new UserError(`confirm_name must be the workspace name exactly: "${b.ws.name}".`);
        const n = await eraseWorkspace(b);
        return { deleted: true, workspace: b.ws.name, documents_removed: n };
      }),
  );
};

/** createPersonalWorkspace: the workspace first, then its roles, the owner's membership and the default categories. */
export async function createWorkspace(c: Ctx, name: string, currency: string, tz: string) {
  const id = newDocId();
  const uid = c.actor.uid;
  const commit = async (writes: Write[], what: string) => {
    try {
      await c.fs.commit(writes);
    } catch (e) {
      throw explain(e, what);
    }
  };
  await commit(
    [{ kind: 'set', collection: 'workspaces', id, data: { id, name, ownerId: uid, baseCurrency: currency, fyStartMonth: FY_START[currency] ?? 1, timeZone: tz, createdAt: SERVER_TIME } }],
    'create a workspace',
  );
  const writes: Write[] = [];
  let ownerRoleId = '';
  for (const [roleName, permissions] of SYSTEM_ROLES) {
    const rid = newDocId();
    if (roleName === 'Owner') ownerRoleId = rid;
    writes.push({ kind: 'set', collection: 'roles', id: rid, data: { id: rid, workspaceId: id, name: roleName, isSystem: true, permissions, createdAt: SERVER_TIME } });
  }
  const mid = `${id}_${uid}`;
  writes.push({
    kind: 'set', collection: 'memberships', id: mid,
    data: { id: mid, workspaceId: id, uid, roleId: ownerRoleId, status: 'active', joinedAt: SERVER_TIME, email: c.email, displayName: c.actor.name },
  });
  for (const [catName, kind] of DEFAULT_CATEGORIES) {
    const cid = newDocId();
    writes.push({ kind: 'set', collection: 'categories', id: cid, data: { id: cid, workspaceId: id, name: catName, kind, isSystem: true, createdAt: SERVER_TIME } });
  }
  await commit(writes, 'set up the workspace');
  const all = await listWorkspaces(c.fs, uid);
  return { created: true, id, name, currency, time_zone: tz, fy_start_month: FY_START[currency] ?? 1, workspaces_now: all.length };
}

/** AccountEraser.eraseWorkspace, in the same order the rules require. */
export async function eraseWorkspace(b: Books): Promise<number> {
  const fs = b.fs;
  const ws = b.ws.id;
  const del = async (collection: string, ids: string[]) => {
    for (let i = 0; i < ids.length; i += 400) {
      try {
        await fs.commit(ids.slice(i, i + 400).map((id) => ({ kind: 'delete' as const, collection, id })));
      } catch (e) {
        throw explain(e, `delete the workspace's ${collection}`);
      }
    }
    return ids.length;
  };
  const idsOf = async (collection: string) => {
    try {
      return (await fs.where(collection, 'workspaceId', ws)).map((d) => String(d.id));
    } catch (e) {
      if (e instanceof FirestoreError && e.status === 403) return [];
      throw e;
    }
  };
  let n = 0;
  for (const col of ['transactions', 'dues', 'debts', 'budgets', 'contacts', 'accounts', 'invites']) n += await del(col, await idsOf(col));
  const members = await fs.where('memberships', 'workspaceId', ws);
  n += await del('memberships', members.filter((m) => m.uid !== b.ws.ownerId).map((m) => String(m.id)));
  n += await del('workspaces', [ws]);
  for (const col of ['revisions', 'categories', 'roles']) n += await del(col, await idsOf(col));
  n += await del('memberships', [`${ws}_${b.ws.ownerId}`]);
  try {
    const me = await fs.get('users', b.actor.uid);
    if (me?.lastWorkspaceId === ws) await fs.commit([{ kind: 'update', collection: 'users', id: b.actor.uid, data: { lastWorkspaceId: null } }]);
  } catch {
    // Only a convenience for the app's next start.
  }
  return n;
}
