// The workspace history (the append-only `revisions` log the app's Activity
// screen reads) and restoring something deleted from it.
//
// A restore recreates the document under its original id, so everything that
// pointed at it (a transaction's account, a payment's due) points at it again,
// exactly like the app's Undo. It is a fresh create by the person restoring,
// with its own history entry.
//
// What it is restored from: the delete's own snapshot when it has one (every
// delete the connector makes, and the app's from this release on), otherwise
// the record rebuilt from its create and update entries. Records the app
// created without a snapshot and deleted without one cannot be rebuilt; the
// tool says so rather than guess.

import { z } from 'zod';

import { UserError, explain } from '../books.js';
import { FirestoreError, type Plain } from '../firestore.js';
import { READ, WRITE, run, workspaceArg, type Register } from './common.js';

const RESTORABLE = ['accounts', 'categories', 'contacts', 'budgets', 'dues', 'debts', 'transactions'];
const AUDIT = new Set(['id', 'workspaceId', 'createdAt', 'createdBy', 'updatedAt', 'updatedBy']);

const time = (r: Plain) => (r.at instanceof Date ? r.at.getTime() : 0);

/** What a revision is about, in a few words, from its snapshot. */
function label(r: Plain): string | undefined {
  const s = r.snapshot as Plain | undefined;
  if (!s) return undefined;
  for (const k of ['name', 'title', 'label', 'note', 'description']) {
    if (typeof s[k] === 'string' && s[k]) return s[k] as string;
  }
  return undefined;
}

/** The record as it stood before [deletion], or null when history cannot say. */
export function rebuild(revisions: Plain[], deletion: Plain): Plain | null {
  const clean = (m: Plain) => Object.fromEntries(Object.entries(m).filter(([k, v]) => !AUDIT.has(k) && v !== null));
  if (deletion.snapshot) return clean(deletion.snapshot as Plain);
  const before = revisions.filter((r) => time(r) <= time(deletion) && r !== deletion).sort((a, c) => time(a) - time(c));
  // Start from the latest create that carries a snapshot; fold the updates after it.
  let startAt = -1;
  for (let i = before.length - 1; i >= 0; i--) {
    if (before[i]!.action === 'create' && before[i]!.snapshot) {
      startAt = i;
      break;
    }
  }
  if (startAt < 0) return null;
  let doc: Plain = { ...(before[startAt]!.snapshot as Plain) };
  for (const r of before.slice(startAt + 1)) {
    if (r.action === 'delete') return null; // deleted and recreated elsewhere: ambiguous
    if (r.action !== 'update') continue;
    const snap = (r.snapshot as Plain | undefined) ?? {};
    const fields = (r.changedFields as string[] | undefined) ?? Object.keys(snap);
    if (!r.snapshot && fields.length) return null; // an update whose values history didn't keep
    for (const f of fields) {
      if (f in snap) doc[f] = snap[f];
      else delete doc[f]; // cleared
    }
  }
  doc = clean(doc);
  return doc;
}

export const registerHistoryTools: Register = (server, ctx) => {
  server.registerTool(
    'list_activity',
    {
      title: 'Workspace history',
      description:
        'What changed in the workspace, newest first: who added, changed or deleted what, and when. With entity_id, the history of one record. Deleted records marked restorable can be brought back with restore_deleted.',
      inputSchema: {
        ...workspaceArg,
        entity_id: z.string().optional(),
        limit: z.number().int().min(1).max(200).optional(),
      },
      annotations: READ,
    },
    ({ workspace_id, entity_id, limit }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const max = limit ?? 30;
        let revs: Plain[];
        if (entity_id) {
          revs = await b.fs.whereEqual('revisions', { workspaceId: b.ws.id, entityId: entity_id });
        } else {
          revs = await b.fs.where('revisions', 'workspaceId', b.ws.id, 'EQUAL', { orderBy: 'at', descending: true, limit: max });
        }
        revs.sort((a, c) => time(c) - time(a));
        // A delete is restorable when the record is still gone and history can rebuild it.
        const latestByEntity = new Map<string, Plain>();
        for (const r of revs) if (!latestByEntity.has(String(r.entityId))) latestByEntity.set(String(r.entityId), r);
        return {
          entries: revs.slice(0, max).map((r) => ({
            at: r.at instanceof Date ? r.at.toISOString() : undefined,
            action: r.action,
            type: r.entityType,
            entity_id: r.entityId,
            by: (r.by as Plain | undefined)?.name,
            ...(label(r) ? { about: label(r) } : {}),
            ...(r.changedFields ? { changed: r.changedFields } : {}),
            ...(r.action === 'delete' && RESTORABLE.includes(String(r.entityType)) && latestByEntity.get(String(r.entityId)) === r
              ? { restorable: r.snapshot ? true : 'possibly' }
              : {}),
          })),
        };
      }),
  );

  server.registerTool(
    'restore_deleted',
    {
      title: 'Restore something deleted',
      description:
        'Bring back a deleted transaction, account, contact, category, budget, due or debt, under its original id so links to it work again. Find it with list_activity.',
      inputSchema: { ...workspaceArg, entity_id: z.string() },
      annotations: WRITE,
    },
    ({ workspace_id, entity_id }) =>
      run(async () => {
        const b = await ctx().books(workspace_id);
        const revs = await b.fs.whereEqual('revisions', { workspaceId: b.ws.id, entityId: entity_id });
        if (!revs.length) throw new UserError(`No history for ${entity_id} in this workspace.`);
        revs.sort((a, c) => time(a) - time(c));
        const last = revs[revs.length - 1]!;
        const collection = String(last.entityType);
        if (!RESTORABLE.includes(collection)) throw new UserError(`A ${collection} record cannot be restored from here.`);
        if (last.action !== 'delete') throw new UserError('That record was not deleted.');
        const data = rebuild(revs, last);
        if (!data) {
          throw new UserError(
            'History does not hold what this record contained (it was created and deleted before the workspace history kept contents), so it cannot be restored.',
          );
        }
        const { writes } = b.createWrites(collection, data, entity_id);
        // Create-only: if the record is back already, nothing is overwritten.
        writes[0]!.mustNotExist = true;
        try {
          await b.fs.commit(writes);
        } catch (e) {
          if (e instanceof FirestoreError && (e.code === 'ALREADY_EXISTS' || e.code === 'FAILED_PRECONDITION' || e.status === 409)) {
            throw new UserError('That record already exists again.');
          }
          throw explain(e, `restore ${collection}`);
        }
        return { restored: true, type: collection, id: entity_id, ...(label({ snapshot: data }) ? { about: label({ snapshot: data }) } : {}) };
      }),
  );
};
