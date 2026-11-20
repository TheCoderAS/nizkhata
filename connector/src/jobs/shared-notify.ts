// Shared ledger notifications: every action on a shared entry is pushed to the
// other person, straight away, at any hour.
//
//   added (expense)     -> the person asked to accept it
//   added (settlement)  -> the person who was paid, to confirm it
//   accepted / rejected -> whoever added it
//
// The backend has no database triggers, so it looks for shared entries whose
// updatedAt moved since it last looked (a cursor in schedulerState/shared,
// read with a two minute overlap so a slow commit is never missed). Each
// (entry, status) is logged in pushLog before it is sent, so overlap,
// restarts and two servers never send one twice. On the very first run the
// cursor starts at "now": history is not replayed.
//
// It follows the entry, not the tool: entries made in the app, by an
// assistant, or on the other person's phone all notify the same way, and the
// person who acted is never the one notified.

import { Firestore, FirestoreError, SERVER_TIME, type Plain } from '../firestore.js';
import type { Push } from './push.js';

export interface SharedNote {
  key: string;
  to: string;
  title: string;
  body: string;
  route: string;
}

const STATE = { collection: 'schedulerState', id: 'shared' };
const OVERLAP_MS = 2 * 60_000;

/** "₹1,500.00" in the entry's own currency, in the reader's date/number locale. */
export function money(amount: number, currency: string, locale = 'en_IN'): string {
  try {
    return new Intl.NumberFormat(locale.replace('_', '-'), { style: 'currency', currency }).format(amount);
  } catch {
    return `${currency} ${amount}`;
  }
}

const currencyOf = (v: unknown) => (typeof v === 'string' && /^[A-Za-z]{3}$/.test(v) ? v.toUpperCase() : 'INR');

/** What a shared entry in its current state should tell whom; null for nothing. */
export function noteFor(e: Plain, locale = 'en_IN'): SharedNote | null {
  const id = String(e.id ?? '');
  const status = String(e.status ?? '');
  const creator = String(e.creatorUid ?? '');
  const other = String(e.counterpartyUid ?? '');
  if (!id || !creator || !other) return null;
  const names = (e.names as Record<string, string> | undefined) ?? {};
  const creatorName = names[creator] || 'Your partner';
  const otherName = names[other] || 'Your partner';
  const what = String(e.description ?? '').trim();
  const amount = money(Number(e.amount ?? 0), currencyOf(e.currency), locale);
  const route = `/shared?entry=${encodeURIComponent(id)}`;
  const settlement = e.kind === 'settlement';
  const key = `shared_${id}_${status}`;

  if (status === 'pending') {
    return settlement
      ? { key, to: other, route, title: `${creatorName} paid you back ${amount}`, body: `${what && what !== 'Settlement' ? `${what}. ` : ''}Tap to confirm it.` }
      : { key, to: other, route, title: `${creatorName} added a shared expense`, body: `${what ? `${what}: ` : ''}${amount} for you to accept.` };
  }
  if (status === 'accepted') {
    return settlement
      ? { key, to: creator, route, title: `${otherName} confirmed your payment`, body: `${amount}${what && what !== 'Settlement' ? ` for ${what}` : ''}.` }
      : { key, to: creator, route, title: `${otherName} accepted ${what || 'your shared expense'}`, body: `${amount}.` };
  }
  if (status === 'rejected') {
    return settlement
      ? { key, to: creator, route, title: `${otherName} did not confirm your payment`, body: `${amount}. Tap to sort it out.` }
      : { key, to: creator, route, title: `${otherName} rejected ${what || 'your shared expense'}`, body: `${amount}. Tap to sort it out.` };
  }
  return null;
}

export class SharedNotifier {
  private busy = false;

  constructor(
    private readonly admin: () => Promise<Firestore>,
    private readonly push: Push,
    private readonly now: () => Date = () => new Date(),
    private readonly log: (m: string) => void = (m) => console.log(m),
  ) {}

  async run(): Promise<{ sent: number }> {
    if (this.busy) return { sent: 0 };
    this.busy = true;
    let sent = 0;
    try {
      const fs = await this.admin();
      const now = this.now();
      const state = await fs.get(STATE.collection, STATE.id);
      const cursor = state?.cursor instanceof Date ? state.cursor : null;
      if (!cursor) {
        // First run ever: start from now rather than replay the whole history,
        // and never look back past this moment (the floor), overlap or not.
        await fs.commit([{ kind: 'set', collection: STATE.collection, id: STATE.id, data: { cursor: now, floor: now } }]);
        return { sent: 0 };
      }
      const floor = state?.floor instanceof Date ? state.floor.getTime() : 0;
      const from = new Date(Math.max(floor, cursor.getTime() - OVERLAP_MS));
      const changed = await fs.where('sharedEntries', 'updatedAt', from, 'GREATER_THAN_OR_EQUAL', {
        orderBy: 'updatedAt',
        limit: 500,
      });
      let newest = cursor;
      for (const e of changed) {
        if (!(e.updatedAt instanceof Date) || e.updatedAt.getTime() < from.getTime()) continue;
        if (e.updatedAt > newest) newest = e.updatedAt;
        try {
          sent += await this.deliver(fs, e);
        } catch (err) {
          this.log(`shared notify ${e.id}: ${(err as Error).message}`);
        }
      }
      if (newest > cursor) {
        await fs.commit([{ kind: 'update', collection: STATE.collection, id: STATE.id, data: { cursor: newest } }]);
      }
    } finally {
      this.busy = false;
    }
    return { sent };
  }

  private async deliver(fs: Firestore, e: Plain): Promise<number> {
    const plain = noteFor(e);
    if (!plain) return 0;
    const devices = (await fs.where('devices', 'uid', plain.to)).filter((d) => typeof d.token === 'string' && d.token);
    if (!devices.length) return 0;
    // Claim it first: whoever logs (entry, status) sends it, nobody else.
    try {
      await fs.commit([
        {
          kind: 'set',
          collection: 'pushLog',
          id: plain.key,
          mustNotExist: true,
          data: { id: plain.key, uid: plain.to, kind: 'shared', date: this.now().toISOString().slice(0, 10), at: SERVER_TIME },
        },
      ]);
    } catch (err) {
      if (err instanceof FirestoreError && (err.code === 'ALREADY_EXISTS' || err.code === 'FAILED_PRECONDITION' || err.status === 409)) return 0;
      throw err;
    }
    let sent = 0;
    for (const d of devices) {
      const note = noteFor(e, typeof d.locale === 'string' && d.locale ? d.locale : 'en_IN')!;
      // Its own channel once the app has one; until then Android files it under
      // the app's default channel.
      const r = await this.push.send(String(d.token), { title: note.title, body: note.body, route: note.route, channel: 'shared_ledger' });
      if (r === 'sent') sent++;
      if (r === 'gone') await fs.commit([{ kind: 'delete', collection: 'devices', id: String(d.id) }]).catch(() => undefined);
    }
    return sent;
  }
}
