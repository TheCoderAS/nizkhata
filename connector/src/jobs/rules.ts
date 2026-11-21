// The app's automatic rules, ported from mobile/lib/services/recurrence.dart,
// statement_cycle.dart and title_tokens.dart so the backend creates exactly
// the documents the app used to. Keep them in step.
//
// The app did its date arithmetic on the phone's local calendar. Here every
// date is a calendar day in the workspace's time zone ({y, m, d}), and a
// stored date is that day's local midnight, which is what the phone wrote.

import { accountDeltas, localParts, parseWhen, type Debt, type Line, type Txn } from '../ledger.js';
import type { Plain } from '../firestore.js';

export interface Cal {
  y: number;
  m: number;
  d: number;
}

/** Normalise like Dart's DateTime(y, m, d): month 13 is next January, day 0 the last of the month before. */
export function norm(y: number, m: number, d: number): Cal {
  const t = new Date(Date.UTC(y, m - 1, d));
  return { y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate() };
}
export const iso = (c: Cal) => `${String(c.y).padStart(4, '0')}-${String(c.m).padStart(2, '0')}-${String(c.d).padStart(2, '0')}`;
export const ymd = (c: Cal) => iso(c).replace(/-/g, '');
export const calOf = (date: Date, tz: string): Cal => {
  const p = localParts(date, tz);
  return { y: p.year, m: p.month, d: p.day };
};
/** Local midnight of [c] in [tz], the instant the app stores for a picked date. */
export const atMidnight = (c: Cal, tz: string) => parseWhen(iso(c), tz);
export const addDays = (c: Cal, n: number) => norm(c.y, c.m, c.d + n);
export const before = (a: Cal, b: Cal) => iso(a) < iso(b);
export const after = (a: Cal, b: Cal) => iso(a) > iso(b);

/** A day of the month, pulled back to the last day of a short month. */
export function dayInMonth(y: number, m: number, day: number): Cal {
  const first = norm(y, m, 1);
  const last = norm(first.y, first.m + 1, 0).d;
  return { y: first.y, m: first.m, d: Math.min(day, last) };
}

// ---- title tokens ----------------------------------------------------------

const TOKEN = /\{\{|\{([A-Za-z#]+)([+-]\d+)?\}/g;
const intlLocale = (l: string) => l.replace('_', '-');
const utc = (c: Cal) => new Date(Date.UTC(c.y, c.m - 1, c.d));

/** formatDate: DateFormat.yMMMd in [locale], e.g. "5 Aug 2026" for en_IN. */
export function formatDate(c: Cal, locale = 'en_IN'): string {
  return new Intl.DateTimeFormat(intlLocale(locale), { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }).format(utc(c));
}

function fyLabel(c: Cal, fyStartMonth: number): string {
  const startYear = c.m >= fyStartMonth ? c.y : c.y - 1;
  if (fyStartMonth === 1) return `${startYear}`;
  return `${startYear}-${String((startYear + 1) % 100).padStart(2, '0')}`;
}

/** True when [text] carries a placeholder the renderer understands (title_tokens.dart hasTokens). */
export function hasTokens(text: string | null | undefined): boolean {
  if (!text) return false;
  for (const m of text.matchAll(TOKEN)) {
    const name = m[1]?.toUpperCase();
    if (name && ['MMM', 'MMMM', 'MM', 'YYYY', 'YY', 'D', 'DD', 'DATE', 'Q', 'FY', '#'].includes(name)) return true;
  }
  return false;
}

export function renderTokens(pattern: string, date: Cal, o: { occurrence?: number; fyStartMonth?: number; locale?: string } = {}): string {
  if (!pattern) return pattern;
  const occurrence = o.occurrence ?? 1;
  const fy = o.fyStartMonth ?? 4;
  const locale = intlLocale(o.locale ?? 'en_IN');
  return pattern.replace(TOKEN, (whole, name: string | undefined, off: string | undefined) => {
    if (whole === '{{') return '{';
    const offset = off ? Number(off) : 0;
    const byMonth = norm(date.y, date.m + offset, 1);
    const byYear = norm(date.y + offset, date.m, 1);
    const byDay = norm(date.y, date.m, date.d + offset);
    const byQuarter = norm(date.y, date.m + offset * 3, 1);
    switch (name!.toUpperCase()) {
      case 'MMM':
        return new Intl.DateTimeFormat(locale, { month: 'short', timeZone: 'UTC' }).format(utc(byMonth));
      case 'MMMM':
        return new Intl.DateTimeFormat(locale, { month: 'long', timeZone: 'UTC' }).format(utc(byMonth));
      case 'MM':
        return String(byMonth.m).padStart(2, '0');
      case 'YYYY':
        return String(byYear.y);
      case 'YY':
        return String(byYear.y % 100).padStart(2, '0');
      case 'D':
        return String(byDay.d);
      case 'DD':
        return String(byDay.d).padStart(2, '0');
      case 'DATE':
        return formatDate(byDay, o.locale ?? 'en_IN');
      case 'Q':
        return `Q${Math.floor((byQuarter.m - 1) / 3) + 1}`;
      case 'FY':
        return fyLabel(byYear, fy);
      case '#':
        return String(occurrence + offset);
      default:
        return whole; // unknown token: left exactly as typed
    }
  });
}

// ---- recurring dues --------------------------------------------------------

export function nextOccurrence(from: Cal, freq: string): Cal {
  switch (freq) {
    case 'weekly':
      return addDays(from, 7);
    case 'yearly':
      return dayInMonth(from.y + 1, from.m, from.d);
    case 'monthly':
    default:
      return dayInMonth(from.y, from.m + 1, from.d);
  }
}

export const recurringDueId = (seriesId: string, c: Cal) => `rec_${seriesId}_${ymd(c)}`;

export interface DueInstance {
  id: string;
  template: Plain;
  dueDate: Cal;
}

/**
 * The last calendar day that has ended in [tz] at [now]. Scheduled work runs
 * "at the end of the day": from 23:55 a day counts as over, so a run in the
 * last five minutes before midnight acts on it. Before that, yesterday is the
 * last day that has ended.
 */
export function closedDay(now: Date, tz: string, endOfDayMinute = 23 * 60 + 55): Cal {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: tz, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(now);
  const h = Number(parts.find((p) => p.type === 'hour')!.value);
  const m = Number(parts.find((p) => p.type === 'minute')!.value);
  const today = calOf(now, tz);
  return h * 60 + m >= endOfDayMinute ? today : addDays(today, -1);
}

/**
 * Which next instances are due to be created. At the end of each due's own
 * date the next one in its series is created, whatever became of this one
 * (paid, unpaid or cancelled). Only the newest instance of a series spawns, a
 * series whose newest instance no longer repeats has ended, and an instance
 * someone deleted ([deleted]) is never made again, which also ends the series
 * if it was the newest. Existing ids make it idempotent.
 */
export function missingDueInstances(dues: Plain[], lastClosed: Cal, tz: string, deleted: Set<string> = new Set()): DueInstance[] {
  const ids = new Set(dues.map((d) => String(d.id)));
  const out: DueInstance[] = [];
  const dateOf = (d: Plain) => (d.dueDate instanceof Date ? d.dueDate : new Date(0));
  for (const d of dues) {
    const freq = d.recurrence as string | undefined;
    if (!freq) continue;
    const due = calOf(dateOf(d), tz);
    if (after(due, lastClosed)) continue; // its day has not ended yet
    const seriesId = String(d.recurrenceId ?? d.id);
    const next = nextOccurrence(due, freq);
    const id = recurringDueId(seriesId, next);
    if (ids.has(id) || deleted.has(id)) continue;
    const isLatest = !dues.some(
      (o) => o.id !== d.id && String(o.recurrenceId ?? o.id) === seriesId && dateOf(o).getTime() > dateOf(d).getTime(),
    );
    if (!isLatest) continue;
    out.push({ id, template: d, dueDate: next });
  }
  return out;
}

/** The document for a spawned instance: the template's fields, with title and note re-rendered. */
export function nextDueDoc(inst: DueInstance, o: { fyStartMonth: number; tz: string; locale?: string }): Plain {
  const t = inst.template;
  const occurrence = Number(t.occurrence ?? 1) + 1;
  const render = (pattern: unknown, fallback: unknown) =>
    typeof pattern === 'string'
      ? renderTokens(pattern, inst.dueDate, { occurrence, fyStartMonth: o.fyStartMonth, locale: o.locale })
      : (fallback as string | undefined);
  return {
    direction: t.direction,
    title: render(t.titlePattern, t.title) ?? '',
    amount: t.amount,
    dueDate: atMidnight(inst.dueDate, o.tz),
    contactId: t.contactId,
    accountId: t.accountId,
    categoryId: t.categoryId,
    note: render(t.notePattern, t.note),
    lines: (t.lines as Plain[] | undefined) ?? [],
    recurrence: t.recurrence,
    recurrenceId: t.recurrenceId ?? t.id,
    titlePattern: t.titlePattern,
    notePattern: t.notePattern,
    occurrence,
  };
}

// ---- credit card statements ------------------------------------------------

export interface Card {
  id: string;
  name: string;
  openingBalance: number;
  statementDay: number;
  paymentDueDay: number;
}

export function cardOf(a: Plain): Card | null {
  if (a.type !== 'credit_card' || a.statementDay == null || a.paymentDueDay == null) return null;
  return {
    id: String(a.id),
    name: String(a.name ?? ''),
    openingBalance: Number(a.openingBalance ?? 0),
    statementDay: Number(a.statementDay),
    paymentDueDay: Number(a.paymentDueDay),
  };
}

export interface Cycle {
  periodStart: Cal;
  statementDate: Cal;
  paymentDue: Cal;
}

export function paymentDueAfter(statement: Cal, dueDay: number): Cal {
  const sameMonth = dayInMonth(statement.y, statement.m, dueDay);
  if (after(sameMonth, statement)) return sameMonth;
  return dayInMonth(statement.y, statement.m + 1, dueDay);
}

export function cycleEndingOn(card: Card, statement: Cal): Cycle {
  const previous = dayInMonth(statement.y, statement.m - 1, card.statementDay);
  return { periodStart: addDays(previous, 1), statementDate: statement, paymentDue: paymentDueAfter(statement, card.paymentDueDay) };
}

export function latestStatement(card: Card, today: Cal): Cycle {
  let statement = dayInMonth(today.y, today.m, card.statementDay);
  if (after(statement, today)) statement = dayInMonth(today.y, today.m - 1, card.statementDay);
  return cycleEndingOn(card, statement);
}

type Round = (n: number) => number;

export function statementOutstanding(card: Card, txns: Txn[], debts: Map<string, Debt>, on: Cal, tz: string, round: Round): number {
  const cutoff = atMidnight(addDays(on, 1), tz).getTime();
  let balance = card.openingBalance;
  for (const t of txns) {
    if (t.date.getTime() >= cutoff) continue;
    balance += accountDeltas(t, debts, round).get(card.id) ?? 0;
  }
  return round(-balance);
}

export function creditedSince(card: Card, txns: Txn[], debts: Map<string, Debt>, since: Cal, until: Cal | null, tz: string, round: Round): number {
  const from = atMidnight(addDays(since, 1), tz).getTime();
  const to = until ? atMidnight(addDays(until, 1), tz).getTime() : null;
  let total = 0;
  for (const t of txns) {
    const at = t.date.getTime();
    if (at < from) continue;
    if (to !== null && at >= to) continue;
    const delta = accountDeltas(t, debts, round).get(card.id) ?? 0;
    if (delta > 0) total += delta;
  }
  return round(total);
}

export const statementDueId = (accountId: string, statement: Cal) => `stmt_${accountId}_${ymd(statement)}`;

export function statementDueDoc(card: Card, cycle: Cycle, outstanding: number, o: { tz: string; locale?: string; round: Round }): Plain {
  const id = statementDueId(card.id, cycle.statementDate);
  const amount = o.round(outstanding);
  const lines: Line[] = [
    { lineId: `${id}_out`, type: 'transfer_out', amount, toAccountId: card.id },
    { lineId: `${id}_in`, type: 'transfer_in', amount, toAccountId: card.id },
  ];
  return {
    direction: 'payable',
    title: `${card.name} bill`,
    amount,
    dueDate: atMidnight(cycle.paymentDue, o.tz),
    note: `Statement of ${formatDate(cycle.statementDate, o.locale)}`,
    lines,
    statementAccountId: card.id,
    statementDate: atMidnight(cycle.statementDate, o.tz),
  };
}

export interface StatementPlan {
  dueId: string;
  doc: Plain;
  kind: 'create' | 'update' | 'cancel' | 'restore';
}

/**
 * The bills that ought to exist now, and those whose amount drifted: only each
 * card's CURRENT statement; left alone once part paid or cancelled by hand.
 */
export function statementDuePlans(o: {
  accounts: Plain[];
  dues: Plain[];
  txns: Txn[];
  debts: Map<string, Debt>;
  settledOf: (dueId: string) => number;
  today: Cal;
  tz: string;
  locale?: string;
  round: Round;
}): StatementPlan[] {
  const byId = new Map(o.dues.map((d) => [String(d.id), d]));
  const out: StatementPlan[] = [];
  for (const a of o.accounts) {
    const card = cardOf(a);
    if (!card) continue;
    const cycle = latestStatement(card, o.today);
    const billed = statementOutstanding(card, o.txns, o.debts, cycle.statementDate, o.tz, o.round);
    const paidSince = creditedSince(card, o.txns, o.debts, cycle.statementDate, o.today, o.tz, o.round);
    const owesNothing = billed <= 0.005;
    const isPaid = !owesNothing && o.round(billed - paidSince) <= 0.005;
    const id = statementDueId(card.id, cycle.statementDate);
    const existing = byId.get(id);

    if (owesNothing) {
      if (existing && existing.status !== 'cancelled' && o.settledOf(id) <= 0.005) {
        out.push({ dueId: id, doc: { status: 'cancelled', autoWithdrawn: true }, kind: 'cancel' });
      }
      continue;
    }
    const doc = statementDueDoc(card, cycle, billed, o);
    if (!existing) {
      if (isPaid) continue;
      out.push({ dueId: id, doc, kind: 'create' });
      continue;
    }
    if (existing.status === 'cancelled') {
      if (existing.autoWithdrawn === true && o.settledOf(id) <= 0.005 && !isPaid) {
        out.push({ dueId: id, doc: { status: 'open', autoWithdrawn: false, amount: doc.amount, lines: doc.lines }, kind: 'restore' });
      }
      continue;
    }
    if (o.settledOf(id) > 0.005) continue;
    if (Math.abs(Number(existing.amount ?? 0) - billed) > 0.005) {
      out.push({ dueId: id, doc: { amount: doc.amount, lines: doc.lines }, kind: 'update' });
    }
  }
  return out;
}
