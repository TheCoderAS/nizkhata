// The backend's scheduled work, which the app used to do on the phone:
//   - create the next instance of every repeating due (recurrence.dart),
//   - raise and keep in step each credit card's bill (statement_cycle.dart),
//   - send due-day reminders as push notifications (due_reminders.dart): one
//     per time slot (9:00, 12:00, 15:00, 18:00, 21:00 local) on a day with
//     unsettled dues, "You have N dues to clear today".
//
// Every write is idempotent, so a run can be repeated, or catch up after the
// service was down, without doing anything twice: dues use the app's
// deterministic ids and are created only if absent; each reminder is logged
// under a (person, day, slot) id before it is sent.
//
// It acts as "Niz Khata" (uid "system") in the workspace history, and runs with
// the service account, never with anyone's sign-in.

import { Books, workspaceTimeZone, type Actor, type WorkspaceInfo } from '../books.js';
import { Firestore, FirestoreError, SERVER_TIME, type Plain } from '../firestore.js';
import { dueSettledAmount, dueStatusFromSettled, makeRound, type Debt } from '../ledger.js';
import type { Push } from './push.js';
import { calOf, closedDay, iso, missingDueInstances, nextDueDoc, statementDuePlans, type Cal } from './rules.js';

/** What a run did, for /healthz: counts and error kinds only, never ids or names. */
export interface RunReport {
  at: string;
  workspaces?: number;
  created?: number;
  updated?: number;
  sent?: number;
  errors: number;
  firstError?: string;
}

/** An error, reduced to something safe to show publicly. */
export function errorKind(e: unknown): string {
  if (e instanceof FirestoreError) return `Firestore ${e.code}${e.status ? ` (${e.status})` : ''}`;
  const m = (e as Error)?.message ?? String(e);
  return m.replace(/[A-Za-z0-9_-]{15,}/g, '…').slice(0, 120);
}

export const SYSTEM: Actor = { uid: 'system', name: 'Niz Khata' };
export const SLOTS = [9, 12, 15, 18, 21];

export interface SchedulerOptions {
  /** A Firestore client with admin access (fresh token each run). */
  admin: () => Promise<Firestore>;
  push: Push | null;
  defaultTimeZone: string;
  now?: () => Date;
  log?: (msg: string) => void;
}

const conflict = (e: unknown) =>
  e instanceof FirestoreError && (e.code === 'ALREADY_EXISTS' || e.code === 'FAILED_PRECONDITION' || e.status === 409);

function localHour(at: Date, tz: string): number {
  const h = new Intl.DateTimeFormat('en-US', { timeZone: tz, hour: '2-digit', hourCycle: 'h23' }).format(at);
  return Number(h);
}

interface Device {
  id: string;
  uid: string;
  token: string;
  timeZone: string;
  locale: string;
  updatedAt: number;
}

export class Scheduler {
  private readonly now: () => Date;
  private readonly log: (m: string) => void;
  private materialising = false;
  lastDues: RunReport | null = null;
  lastReminders: RunReport | null = null;
  private reminding = false;
  /** (person, day, slot) already handled by this process; the push log guards across restarts. */
  private readonly handled = new Set<string>();

  constructor(private readonly o: SchedulerOptions) {
    this.now = o.now ?? (() => new Date());
    this.log = o.log ?? ((m) => console.log(m));
  }

  /**
   * The phones to notify: one record per push token, the most recent
   * sign-in's. A phone that changed hands while its old record could not be
   * removed (signed out offline) carries the same token under two people;
   * only whoever signed in last is notified, and the stale record is removed.
   */
  private async devices(fs: Firestore): Promise<Device[]> {
    const all = (await fs.all('devices'))
      .filter((d) => typeof d.uid === 'string' && typeof d.token === 'string' && d.token)
      .map((d) => ({
        id: String(d.id),
        uid: String(d.uid),
        token: String(d.token),
        timeZone: typeof d.timeZone === 'string' && d.timeZone ? d.timeZone : this.o.defaultTimeZone,
        locale: typeof d.locale === 'string' && d.locale ? d.locale : 'en_IN',
        updatedAt: d.updatedAt instanceof Date ? d.updatedAt.getTime() : 0,
      }));
    const byToken = new Map<string, Device>();
    const stale: Device[] = [];
    for (const d of all) {
      const cur = byToken.get(d.token);
      if (!cur) byToken.set(d.token, d);
      else if (d.updatedAt > cur.updatedAt) {
        stale.push(cur);
        byToken.set(d.token, d);
      } else stale.push(d);
    }
    if (stale.length) {
      await fs.commit(stale.map((d) => ({ kind: 'delete' as const, collection: 'devices', id: d.id }))).catch(() => undefined);
    }
    return [...byToken.values()];
  }

  /** Where a workspace's calendar is: its owner's phone, else the default. */
  private placeOf(ownerId: string, devices: Device[]) {
    const mine = devices.filter((d) => d.uid === ownerId).sort((a, b) => b.updatedAt - a.updatedAt)[0];
    return { tz: mine?.timeZone ?? this.o.defaultTimeZone, locale: mine?.locale ?? 'en_IN' };
  }

  // ---- repeating dues and card bills ---------------------------------------

  async materialise(): Promise<{ created: number; updated: number }> {
    if (this.materialising) return { created: 0, updated: 0 };
    this.materialising = true;
    let created = 0;
    let updated = 0;
    try {
      const fs = await this.o.admin();
      const [workspaces, devices] = await Promise.all([fs.all('workspaces'), this.devices(fs)]);
      await this.pruneLog(fs).catch((e) => this.log(`push log cleanup: ${(e as Error).message}`));
      let errors = 0;
      let firstError: string | undefined;
      for (const w of workspaces) {
        try {
          const r = await this.materialiseWorkspace(fs, w, devices);
          created += r.created;
          updated += r.updated;
          errors += r.errors;
          firstError ??= r.firstError;
        } catch (e) {
          errors++;
          firstError ??= errorKind(e);
          this.log(`materialise ${w.id}: ${(e as Error).message}`);
        }
      }
      this.lastDues = { at: this.now().toISOString(), workspaces: workspaces.length, created, updated, errors, ...(firstError ? { firstError } : {}) };
    } catch (e) {
      this.lastDues = { at: this.now().toISOString(), errors: 1, firstError: errorKind(e) };
      throw e;
    } finally {
      this.materialising = false;
    }
    this.log(`dues run: ${created} created, ${updated} updated, ${this.lastDues?.errors ?? 0} errors`);
    return { created, updated };
  }

  private async materialiseWorkspace(fs: Firestore, w: Plain, devices: Device[]) {
    // The workspace's own time zone decides when its days end; the owner's
    // phone only lends its date format to rendered titles.
    const tz = workspaceTimeZone(w);
    const { locale } = this.placeOf(String(w.ownerId ?? ''), devices);
    const info: WorkspaceInfo = {
      id: String(w.id),
      name: String(w.name ?? ''),
      currency: String(w.baseCurrency ?? 'INR'),
      fyStartMonth: Number(w.fyStartMonth ?? 4),
      ownerId: String(w.ownerId ?? ''),
      timeZone: tz,
    };
    const b = Books.forWorkspace(fs, SYSTEM, info, tz);
    const lastClosed = closedDay(this.now(), tz);
    const dues = await b.load('dues');
    let created = 0;
    let updated = 0;
    let errors = 0;
    let firstError: string | undefined;

    // Dues someone deleted are never made again: deleting the newest of a
    // series, or a card bill, is how a person says "not this one".
    const deleted = new Set(
      (await fs.whereEqual('revisions', { workspaceId: info.id, entityType: 'dues', action: 'delete' })).map((r) => String(r.entityId)),
    );

    // Repeating dues, caught up to the last day that has ended.
    for (let pass = 0; pass < 120; pass++) {
      const missing = missingDueInstances(dues, lastClosed, tz, deleted);
      if (!missing.length) break;
      for (const inst of missing) {
        const data = { ...nextDueDoc(inst, { fyStartMonth: info.fyStartMonth, tz, locale }), status: 'open' };
        const { writes } = b.createWrites('dues', data, inst.id);
        writes[0]!.mustNotExist = true;
        try {
          await fs.commit(writes);
          created++;
        } catch (e) {
          if (!conflict(e)) throw e;
        }
        dues.push({ ...data, id: inst.id });
      }
    }

    // Card bills.
    const accounts = await b.load('accounts');
    if (accounts.some((a) => a.type === 'credit_card' && a.statementDay != null && a.paymentDueDay != null)) {
      const [txns, debts] = await Promise.all([b.txns(), b.debts()]);
      const round = makeRound(info.currency);
      const settledOf = (id: string) => dueSettledAmount({ id, amount: 0, status: 'open' }, txns, round);
      const plans = statementDuePlans({
        accounts,
        dues,
        txns,
        debts: new Map<string, Debt>(debts.map((d) => [d.id, d])),
        settledOf,
        // A statement is billed once its day is over.
        today: lastClosed,
        tz,
        locale,
        round,
      });
      for (const p of plans) {
        if (p.kind === 'create' && deleted.has(p.dueId)) continue;
        try {
          if (p.kind === 'create') {
            const { writes } = b.createWrites('dues', { ...p.doc, status: 'open' }, p.dueId);
            writes[0]!.mustNotExist = true;
            await fs.commit(writes);
            created++;
          } else {
            await fs.commit(b.updateWrites('dues', p.dueId, p.doc));
            updated++;
          }
        } catch (e) {
          if (!conflict(e)) {
            errors++;
            firstError ??= errorKind(e);
            this.log(`statement bill ${p.dueId}: ${(e as Error).message}`);
          }
        }
      }
    }
    return { created, updated, errors, firstError };
  }

  // ---- reminders -----------------------------------------------------------

  async remind(): Promise<{ sent: number }> {
    const push = this.o.push;
    if (this.reminding || !push) return { sent: 0 };
    if (this.handled.size > 50_000) this.handled.clear();
    this.reminding = true;
    let sent = 0;
    try {
      const fs = await this.o.admin();
      const devices = await this.devices(fs);
      const now = this.now();
      let remindErrors = 0;
      let remindFirst: string | undefined;
      const byUser = new Map<string, Device[]>();
      for (const d of devices) byUser.set(d.uid, [...(byUser.get(d.uid) ?? []), d]);

      const wsCache = new Map<string, Promise<Plain | null>>();
      const workspace = (id: string) => {
        let p = wsCache.get(id);
        if (!p) wsCache.set(id, (p = fs.get('workspaces', id)));
        return p;
      };
      const duesCache = new Map<string, Promise<Plain[]>>();
      const duesOf = (id: string) => {
        let p = duesCache.get(id);
        if (!p) duesCache.set(id, (p = fs.where('dues', 'workspaceId', id)));
        return p;
      };
      const paidCache = new Map<string, Promise<Plain[]>>();
      const txnsOf = (id: string) => {
        let p = paidCache.get(id);
        if (!p) paidCache.set(id, (p = fs.where('transactions', 'workspaceId', id)));
        return p;
      };

      for (const [uid, phones] of byUser) {
        try {
          // One reminder per workspace, named, on its own calendar and clock:
          // "today" and the 9:00 slot are the workspace's. Tapping it opens
          // that workspace's day.
          for (const m of await fs.where('memberships', 'uid', uid)) {
            const wsId = String(m.workspaceId ?? '');
            if (!wsId) continue;
            const w = await workspace(wsId);
            if (!w) continue;
            const tz = workspaceTimeZone(w);
            const slot = SLOTS.filter((h) => h <= localHour(now, tz)).at(-1);
            if (slot === undefined) continue;
            const today = calOf(now, tz);
            const key = this.reminderKey(uid, wsId, today, slot);
            if (this.handled.has(key)) continue;
            const n = await this.countDueToday(fs, m, wsId, w, today, tz, duesOf, txnsOf);
            if (n > 0 && (await this.claim(fs, key, uid, today, slot, n))) {
              const name = String(w.name ?? '').trim() || 'Niz Khata';
              for (const d of phones) {
                const r = await push.send(d.token, {
                  title: `${name}: ${n === 1 ? 'a due to clear today' : `${n} dues to clear today`}`,
                  body: "Tap to see what's due",
                  route: `/dues-day?date=${iso(today)}&ws=${encodeURIComponent(wsId)}`,
                  channel: 'due_reminders',
                  tag: `dues_${wsId}_${iso(today)}`,
                });
                if (r === 'sent') sent++;
                if (r === 'gone') await fs.commit([{ kind: 'delete', collection: 'devices', id: d.id }]).catch(() => undefined);
              }
            }
            this.handled.add(key);
          }
        } catch (e) {
          remindErrors++;
          remindFirst ??= errorKind(e);
          this.log(`reminder ${uid}: ${(e as Error).message}`);
        }
      }
      this.lastReminders = { at: this.now().toISOString(), sent, errors: remindErrors, ...(remindFirst ? { firstError: remindFirst } : {}) };
    } catch (e) {
      this.lastReminders = { at: this.now().toISOString(), sent, errors: 1, firstError: errorKind(e) };
      throw e;
    } finally {
      this.reminding = false;
    }
    return { sent };
  }

  /** One reminder per person, workspace, day and slot. */
  private reminderKey(uid: string, wsId: string, today: Cal, slot: number): string {
    return `${uid}_${wsId}_${iso(today)}_${slot}`;
  }

  /** Unsettled dues on [today] in one workspace that membership [m] may see. */
  private async countDueToday(
    fs: Firestore,
    m: Plain,
    wsId: string,
    w: Plain,
    today: Cal,
    tz: string,
    duesOf: (id: string) => Promise<Plain[]>,
    txnsOf: (id: string) => Promise<Plain[]>,
  ): Promise<number> {
    const role = m.roleId ? await fs.get('roles', String(m.roleId)) : null;
    const permissions = (role?.permissions as Record<string, boolean> | undefined) ?? {};
    if (permissions['dues.view'] !== true) return 0;
    const own = permissions['scope.own'] === true;
    const linked = m.linkedContactId as string | undefined;
    if (own && !linked) return 0;
    const todays = (await duesOf(wsId)).filter(
      (d) => (!own || d.contactId === linked) && d.dueDate instanceof Date && iso(calOf(d.dueDate, tz)) === iso(today),
    );
    if (!todays.length) return 0;
    const round = makeRound(String(w.baseCurrency ?? 'INR'));
    const linkedTxns = (await txnsOf(wsId)).map((t) => ({ id: String(t.id), dueId: t.dueId as string | undefined, totalAmount: Number(t.totalAmount ?? 0) }));
    let n = 0;
    for (const d of todays) {
      const due = { id: String(d.id), amount: Number(d.amount ?? 0), status: String(d.status ?? 'open') };
      const st = dueStatusFromSettled(due, dueSettledAmount(due, linkedTxns as never, round));
      if (st === 'open' || st === 'partial') n++;
    }
    return n;
  }

  /** The reminder log is kept 30 days (the privacy policy says so), then cleared. */
  async pruneLog(fs: Firestore): Promise<number> {
    const cutoff = new Date(this.now().getTime() - 30 * 86_400_000).toISOString().slice(0, 10);
    const old = await fs.where('pushLog', 'date', cutoff, 'LESS_THAN', { limit: 400 });
    if (old.length) await fs.commit(old.map((d) => ({ kind: 'delete' as const, collection: 'pushLog', id: String(d.id) })));
    return old.length;
  }

  /** Log the reminder before sending it; false when another run already did. */
  private async claim(fs: Firestore, key: string, uid: string, today: Cal, slot: number, count: number): Promise<boolean> {
    try {
      await fs.commit([
        { kind: 'set', collection: 'pushLog', id: key, mustNotExist: true, data: { id: key, uid, date: iso(today), slot, count, kind: 'due_reminder', at: SERVER_TIME } },
      ]);
      return true;
    } catch (e) {
      if (conflict(e)) return false;
      throw e;
    }
  }

  /** Run the reminders every [remindEveryMs] and the dues every [materialiseEveryMs], starting now. */
  start(remindEveryMs = 5 * 60_000, materialiseEveryMs = 5 * 60_000): () => void {
    const safe = (f: () => Promise<unknown>) => () => void f().catch((e) => this.log(`scheduler: ${(e as Error).message}`));
    const m = safe(() => this.materialise());
    const r = safe(() => this.remind());
    // Dues first (a repeating due created now may be due today), then reminders.
    setTimeout(() => void this.materialise().catch(() => undefined).finally(r), 5_000);
    const t1 = setInterval(r, remindEveryMs);
    const t2 = setInterval(m, materialiseEveryMs);
    return () => {
      clearInterval(t1);
      clearInterval(t2);
    };
  }
}
