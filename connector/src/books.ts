// One person's view of one workspace, and the writes the app makes.
//
// The write helpers mirror mobile/lib/data/mutations.dart: the same document
// fields, the same createdBy/updatedBy actors and server timestamps, and the
// same `revisions` entry in the same atomic commit, so the app reads what the
// connector writes as if it had written it itself, and the workspace history
// shows who made the change.

import { DELETE, Firestore, FirestoreError, newDocId, SERVER_TIME, type Plain, type Write } from './firestore.js';
import { makeRound, type Debt, type Due, type Line, type Txn } from './ledger.js';

export interface Actor {
  uid: string;
  name: string;
}

export class UserError extends Error {}

const IGNORED_REVISION_FIELDS = new Set(['id', 'workspaceId', 'createdAt', 'createdBy', 'updatedAt', 'updatedBy']);

/** Drop nulls/undefined, as the app's _strip does on create. */
export function strip(m: Plain): Plain {
  const out: Plain = {};
  for (const [k, v] of Object.entries(m)) if (v !== null && v !== undefined) out[k] = v;
  return out;
}

function sanitize(m: Plain): Plain {
  const out: Plain = {};
  for (const [k, v] of Object.entries(m)) {
    if (v === null || v === undefined || v === DELETE || IGNORED_REVISION_FIELDS.has(k)) continue;
    out[k] = v;
  }
  return out;
}

export interface WorkspaceInfo {
  id: string;
  name: string;
  currency: string;
  fyStartMonth: number;
  ownerId: string;
  /** Where the books' days begin and end; fixed at creation. Older workspaces: India. */
  timeZone: string;
}

/** A workspace's time zone; workspaces made before it was stored keep their books in India time. */
export const DEFAULT_TIME_ZONE = 'Asia/Kolkata';
export function workspaceTimeZone(ws: Plain | null | undefined): string {
  const tz = ws?.timeZone;
  if (typeof tz !== 'string' || !tz) return DEFAULT_TIME_ZONE;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return tz;
  } catch {
    return DEFAULT_TIME_ZONE;
  }
}

export async function listWorkspaces(fs: Firestore, uid: string): Promise<WorkspaceInfo[]> {
  const memberships = await fs.where('memberships', 'uid', uid);
  const out: WorkspaceInfo[] = [];
  for (const m of memberships) {
    const id = String(m.workspaceId ?? '');
    if (!id) continue;
    const ws = await fs.get('workspaces', id).catch(() => null);
    if (!ws) continue;
    out.push({
      id,
      name: String(ws.name ?? 'Workspace'),
      currency: String(ws.baseCurrency ?? 'INR'),
      fyStartMonth: Number(ws.fyStartMonth ?? 4),
      ownerId: String(ws.ownerId ?? ''),
      timeZone: workspaceTimeZone(ws),
    });
  }
  return out;
}

export class Books {
  readonly round: (n: number) => number;

  private constructor(
    readonly fs: Firestore,
    readonly actor: Actor,
    readonly ws: WorkspaceInfo,
    readonly timeZone: string,
  ) {
    this.round = makeRound(ws.currency);
  }

  /**
   * The workspace to act in: the one named, or, when there is only one, that
   * one. With several and none named, refuse and list them, so the assistant
   * asks once instead of guessing. (The app keeps the workspace you have open
   * on the phone only, so there is nothing reliable to default to.)
   */
  static async open(fs: Firestore, actor: Actor, timeZone: string, workspaceId?: string): Promise<Books> {
    const all = await listWorkspaces(fs, actor.uid);
    if (all.length === 0) throw new UserError('This account has no Niz Khata workspace yet. Open the app once to create one.');
    let ws: WorkspaceInfo | undefined;
    if (workspaceId) {
      ws = all.find((w) => w.id === workspaceId);
      if (!ws) throw new UserError(`No workspace with id ${workspaceId}. Call list_workspaces to see yours.`);
    } else if (all.length === 1) {
      ws = all[0];
    } else {
      throw new UserError(
        `This account has ${all.length} workspaces. Ask which one to use, then pass its workspace_id: ` +
          all.map((w) => `${w.name} (${w.id})`).join(', '),
      );
    }
    if (!ws) throw new UserError('No workspace found.');
    // Dates are the workspace's own: its time zone, not the caller's.
    void timeZone;
    return new Books(fs, actor, ws, ws.timeZone);
  }

  /** Books for a workspace already known, for the scheduled jobs' system actor. */
  static forWorkspace(fs: Firestore, actor: Actor, ws: WorkspaceInfo, timeZone: string): Books {
    return new Books(fs, actor, ws, timeZone);
  }

  // ---- reads ----

  async load(collection: string): Promise<Plain[]> {
    try {
      return await this.fs.where(collection, 'workspaceId', this.ws.id);
    } catch (e) {
      throw explain(e, `read ${collection}`);
    }
  }

  async getOne(collection: string, id: string): Promise<Plain> {
    let doc: Plain | null;
    try {
      doc = await this.fs.get(collection, id);
    } catch (e) {
      throw explain(e, `read ${collection}`);
    }
    if (!doc || doc.workspaceId !== this.ws.id) throw new UserError(`No ${singular(collection)} with id ${id} in this workspace.`);
    return doc;
  }

  async txns(): Promise<Txn[]> {
    return (await this.load('transactions')).map(toTxn);
  }

  async debts(): Promise<Array<Debt & Plain>> {
    return (await this.load('debts')).map((d) => ({
      ...d,
      id: String(d.id),
      contactId: String(d.contactId ?? ''),
      direction: String(d.direction ?? 'owe'),
      status: String(d.status ?? 'open'),
      principal: Number(d.principal ?? 0),
    }));
  }

  async dues(): Promise<Array<Due & Plain>> {
    return (await this.load('dues')).map((d) => ({
      ...d,
      id: String(d.id),
      amount: Number(d.amount ?? 0),
      status: String(d.status ?? 'open'),
    }));
  }

  // ---- write building blocks (mutations.dart) ----

  private by() {
    return { uid: this.actor.uid, name: this.actor.name };
  }

  revision(entityType: string, entityId: string, action: 'create' | 'update' | 'delete', snapshot?: Plain, changedFields?: string[]): Write {
    const id = newDocId();
    const rev: Plain = {
      id,
      workspaceId: this.ws.id,
      entityType,
      entityId,
      action,
      by: this.by(),
      at: SERVER_TIME,
    };
    if (snapshot) rev.snapshot = sanitize(snapshot);
    if (changedFields && changedFields.length) rev.changedFields = changedFields;
    return { kind: 'set', collection: 'revisions', id, data: rev };
  }

  createWrites(collection: string, data: Plain, id = newDocId(), snapshotOnRevision = true): { id: string; writes: Write[] } {
    const clean = strip(data);
    return {
      id,
      writes: [
        {
          kind: 'set',
          collection,
          id,
          data: {
            id,
            workspaceId: this.ws.id,
            ...clean,
            createdBy: this.by(),
            createdAt: SERVER_TIME,
            updatedBy: this.by(),
            updatedAt: SERVER_TIME,
          },
        },
        this.revision(collection, id, 'create', snapshotOnRevision ? clean : undefined),
      ],
    };
  }

  /** On update an explicit null clears the field, as in the app. */
  updateWrites(collection: string, id: string, data: Plain, withSnapshot = true): Write[] {
    const update: Plain = {};
    for (const [k, v] of Object.entries(data)) update[k] = v === null ? DELETE : v;
    return [
      { kind: 'update', collection, id, data: { ...update, updatedBy: this.by(), updatedAt: SERVER_TIME } },
      this.revision(collection, id, 'update', withSnapshot ? strip(data) : undefined, withSnapshot ? Object.keys(data) : undefined),
    ];
  }

  /**
   * With [snapshot] (the document as it stood), the delete revision keeps its
   * contents, so restore_deleted can bring it back exactly as it was.
   */
  deleteWrites(collection: string, id: string, snapshot?: Plain): Write[] {
    return [{ kind: 'delete', collection, id }, this.revision(collection, id, 'delete', snapshot)];
  }

  /** A transaction document as _buildTxnDoc makes it. */
  txnDoc(id: string, t: {
    date: Date;
    accountId: string;
    totalAmount: number;
    lines: Line[];
    note?: string | null;
    contactId?: string | null;
    dueId?: string | null;
  }): Plain {
    return {
      id,
      workspaceId: this.ws.id,
      date: t.date,
      accountId: t.accountId,
      totalAmount: t.totalAmount,
      hasSplit: t.lines.length > 1,
      financialYear: '', // filled by caller
      createdBy: this.by(),
      createdAt: SERVER_TIME,
      updatedBy: this.by(),
      updatedAt: SERVER_TIME,
      lines: t.lines.map((l) => strip(l as unknown as Plain)),
      ...strip({ note: t.note, contactId: t.contactId, dueId: t.dueId }),
    };
  }

  async commit(writes: Write[], what: string): Promise<void> {
    try {
      await this.fs.commit(writes);
    } catch (e) {
      throw explain(e, what);
    }
  }
}

export function toTxn(d: Plain): Txn {
  return {
    id: String(d.id),
    date: d.date instanceof Date ? d.date : new Date(0),
    accountId: String(d.accountId ?? ''),
    totalAmount: Number(d.totalAmount ?? 0),
    lines: ((d.lines as Plain[] | undefined) ?? []).map((l) => ({
      ...(l as object),
      lineId: String(l.lineId ?? ''),
      type: String(l.type ?? ''),
      amount: Number(l.amount ?? 0),
    })) as Line[],
    contactId: d.contactId ? String(d.contactId) : undefined,
    dueId: d.dueId ? String(d.dueId) : undefined,
    note: d.note ? String(d.note) : undefined,
  };
}

function singular(c: string): string {
  return ({ categories: 'category', dues: 'due', debts: 'debt', budgets: 'budget', contacts: 'contact', transactions: 'transaction', accounts: 'account' } as Record<string, string>)[c] ?? c;
}

/** Turn a Firestore refusal into something a person can act on. */
export function explain(e: unknown, what: string): Error {
  if (e instanceof FirestoreError) {
    if (e.status === 403 || e.code === 'PERMISSION_DENIED') {
      return new UserError(`Your role in this workspace does not allow you to ${what}.`);
    }
    if (e.status === 404 || e.code === 'NOT_FOUND') return new UserError(`Not found while trying to ${what}.`);
    return new Error(`Could not ${what}: ${e.code} ${e.message}`);
  }
  return e instanceof Error ? e : new Error(String(e));
}
