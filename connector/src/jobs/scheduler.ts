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

import { Books, type Actor, type WorkspaceInfo } from '../books.js';
import { Firestore, FirestoreError, SERVER_TIME, type Plain } from '../firestore.js';
import { dueSettledAmount, dueStatusFromSettled, makeRound, type Debt } from '../ledger.js';
import type { Push } from './push.js';
import { calOf, iso, missingDueInstances, nextDueDoc, statementDuePlans, type Cal } from './rules.js';

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
  private reminding = false;
  /** (person, day, slot) already handled by this process; the push log guards across restarts. */
  private readonly handled = new Set<string>();

  constructor(private readonly o: SchedulerOptions) {
    this.now = o.now ?? (() => new Date());
    this.log = o.log ?? ((m) => console.log(m));
  }

  private async devices(fs: Firestore): Promise<Device[]> {
    return (await fs.all('devices'))
      .filter((d) => typeof d.uid === 'string' && typeof d.token === 'string' && d.token)
      .map((d) => ({
        id: String(d.id),
        uid: String(d.uid),
        token: String(d.token),
        timeZone: typeof d.timeZone === 'string' && d.timeZone ? d.timeZone : this.o.defaultTimeZone,
        locale: typeof d.locale === 'string' && d.locale ? d.locale : 'en_IN',
        updatedAt: d.updatedAt instanceof Date ? d.updatedAt.getTime() : 0,
      }));
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
      for (const w of workspaces) {
        try {
          const r = await this.materialiseWorkspace(fs, w, devices);
          created += r.created;
          updated += r.updated;
        } catch (e) {
          this.log(`materialise ${w.id}: ${(e as Error).message}`);
        }
      }
    } finally {
      this.materialising = false;
    }
    if (created || updated) this.log(`scheduled jobs: ${created} dues created, ${updated} updated`);
    return { created, updated };
  }

  private async materialiseWorkspace(fs: Firestore, w: Plain, devices: Device[]) {
    const { tz, locale } = this.placeOf(String(w.ownerId ?? ''), devices);
    const info: WorkspaceInfo = {
      id: String(w.id),
      name: String(w.name ?? ''),
      currency: String(w.baseCurrency ?? 'INR'),
      fyStartMonth: Number(w.fyStartMonth ?? 4),
      ownerId: String(w.ownerId ?? ''),
    };
    const b = Books.forWorkspace(fs, SYSTEM, info, tz);
    const today = calOf(this.now(), tz);
    const dues = await b.load('dues');
    let created = 0;
    let updated = 0;

    // Repeating dues, caught up to today: an instance created for a past date
    // spawns its own successor on the next pass, as successive syncs did.
    for (let pass = 0; pass < 120; pass++) {
      const missing = missingDueInstances(dues, today, tz);
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
        today,
        tz,
        locale,
        round,
      });
      for (const p of plans) {
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
          if (!conflict(e)) this.log(`statement bill ${p.dueId}: ${(e as Error).message}`);
        }
      }
    }
    return { created, updated };
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
      const groups = new Map<string, Device[]>();
      for (const d of devices) {
        const key = `${d.uid}|${d.timeZone}`;
        groups.set(key, [...(groups.get(key) ?? []), d]);
      }
      const cache = new Map<string, Promise<{ dues: Plain[]; txns: Plain[]; round: (n: number) => number }>>();
      const books = (ws: string) => {
        let p = cache.get(ws);
        if (!p) {
          p = (async () => {
            const w = await fs.get('workspaces', ws);
            const round = makeRound(String(w?.baseCurrency ?? 'INR'));
            const [dues, txns] = await Promise.all([fs.where('dues', 'workspaceId', ws), fs.where('transactions', 'workspaceId', ws)]);
            return { dues, txns, round };
          })();
          cache.set(ws, p);
        }
        return p;
      };

      for (const group of groups.values()) {
        const { uid, timeZone: tz } = group[0]!;
        const slot = SLOTS.filter((h) => h <= localHour(now, tz)).at(-1);
        if (slot === undefined) continue;
        const today = calOf(now, tz);
        const key = `${uid}_${iso(today)}_${slot}`;
        if (this.handled.has(key)) continue;
        try {
          const n = await this.countDueToday(fs, uid, today, tz, books);
          if (n > 0 && (await this.claim(fs, key, uid, today, slot, n))) {
            for (const d of group) {
              const r = await push.send(d.token, {
                title: n === 1 ? 'You have a due to clear today' : `You have ${n} dues to clear today`,
                body: "Tap to see what's due",
                route: `/dues-day?date=${iso(today)}`,
                channel: 'due_reminders',
                tag: `dues_${iso(today)}`,
              });
              if (r === 'sent') sent++;
              if (r === 'gone') await fs.commit([{ kind: 'delete', collection: 'devices', id: d.id }]).catch(() => undefined);
            }
          }
          this.handled.add(key);
        } catch (e) {
          this.log(`reminder ${key}: ${(e as Error).message}`);
        }
      }
    } finally {
      this.reminding = false;
    }
    return { sent };
  }

  /** Unsettled dues on [today] across the workspaces where [uid] may see dues. */
  private async countDueToday(
    fs: Firestore,
    uid: string,
    today: Cal,
    tz: string,
    books: (ws: string) => Promise<{ dues: Plain[]; txns: Plain[]; round: (n: number) => number }>,
  ): Promise<number> {
    let n = 0;
    for (const m of await fs.where('memberships', 'uid', uid)) {
      const ws = String(m.workspaceId ?? '');
      if (!ws) continue;
      const role = m.roleId ? await fs.get('roles', String(m.roleId)) : null;
      const permissions = (role?.permissions as Record<string, boolean> | undefined) ?? {};
      if (permissions['dues.view'] !== true) continue;
      const own = permissions['scope.own'] === true;
      const linked = m.linkedContactId as string | undefined;
      if (own && !linked) continue;
      const { dues, txns, round } = await books(ws);
      const linkedTxns = txns.map((t) => ({ id: String(t.id), dueId: t.dueId as string | undefined, totalAmount: Number(t.totalAmount ?? 0) }));
      for (const d of dues) {
        if (own && d.contactId !== linked) continue;
        if (!(d.dueDate instanceof Date) || iso(calOf(d.dueDate, tz)) !== iso(today)) continue;
        const due = { id: String(d.id), amount: Number(d.amount ?? 0), status: String(d.status ?? 'open') };
        const settled = dueSettledAmount(due, linkedTxns as never, round);
        const st = dueStatusFromSettled(due, settled);
        if (st === 'open' || st === 'partial') n++;
      }
    }
    return n;
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
  start(remindEveryMs = 5 * 60_000, materialiseEveryMs = 30 * 60_000): () => void {
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
