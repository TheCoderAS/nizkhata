// The app's money rules, ported line for line from mobile/lib/data/derive.dart
// so the connector reports exactly the figures the app shows. Keep the two in
// step: a change to one is a change to both.

export interface Line {
  lineId: string;
  type: string;
  amount: number;
  categoryId?: string;
  debtId?: string;
  toAccountId?: string;
  note?: string;
  external?: boolean;
  tax?: Record<string, unknown>;
}

export interface Txn {
  id: string;
  date: Date;
  accountId: string;
  totalAmount: number;
  lines: Line[];
  contactId?: string;
  dueId?: string;
  note?: string;
}

export interface Debt {
  id: string;
  contactId: string;
  direction: 'owe' | 'owed' | string;
  status: string;
  principal: number;
}

export interface Due {
  id: string;
  amount: number;
  status: string;
}

/** Minor units per currency; the app's catalogue (mobile/lib/core/currency.dart). */
const ZERO_DECIMALS = new Set(['JPY', 'KRW', 'IDR']);
const THREE_DECIMALS = new Set(['KWD', 'BHD', 'OMR']);

export function currencyDecimals(code: string): number {
  const c = code.toUpperCase();
  if (ZERO_DECIMALS.has(c)) return 0;
  if (THREE_DECIMALS.has(c)) return 3;
  return 2;
}

export function makeRound(currency: string): (n: number) => number {
  const f = 10 ** currencyDecimals(currency);
  return (n: number) => Math.round((n + 1e-9) * f) / f;
}

const PRIMARY_SIGN: Record<string, number> = {
  income: 1,
  interest_income: 1,
  borrow: 1,
  expense: -1,
  interest_expense: -1,
  fee: -1,
  tax: -1,
  lend: -1,
  transfer_out: -1,
  transfer_in: 0,
  repayment: 0,
};

export const LINE_TYPES = Object.keys(PRIMARY_SIGN);
export const needsCategory = (t: string) =>
  ['income', 'expense', 'fee', 'tax', 'interest_income', 'interest_expense'].includes(t);
export const needsDebt = (t: string) => t === 'borrow' || t === 'lend' || t === 'repayment';
export const isExpenseSpend = (t: string) =>
  t === 'expense' || t === 'interest_expense' || t === 'fee' || t === 'tax';

export function primaryAccountEffect(line: Line, debt: Debt | undefined): number {
  if (line.external) return 0;
  if (line.type === 'repayment') {
    if (!debt) return 0;
    return (debt.direction === 'owe' ? -1 : 1) * line.amount;
  }
  return (PRIMARY_SIGN[line.type] ?? 0) * line.amount;
}

export function accountDeltas(
  txn: Txn,
  debtsById: Map<string, Debt>,
  round: (n: number) => number,
): Map<string, number> {
  const deltas = new Map<string, number>();
  const add = (acct: string, amt: number) => deltas.set(acct, round((deltas.get(acct) ?? 0) + amt));
  for (const line of txn.lines) {
    if (line.type === 'transfer_in') {
      if (line.toAccountId) add(line.toAccountId, line.amount);
      continue;
    }
    add(txn.accountId, primaryAccountEffect(line, line.debtId ? debtsById.get(line.debtId) : undefined));
  }
  return deltas;
}

export function computeTotal(lines: Line[], debtsById: Map<string, Debt>, round: (n: number) => number): number {
  let total = 0;
  for (const l of lines) total += primaryAccountEffect(l, l.debtId ? debtsById.get(l.debtId) : undefined);
  return round(total);
}

export function accountBalances(
  accounts: Array<{ id: string; openingBalance: number }>,
  txns: Txn[],
  debtsById: Map<string, Debt>,
  round: (n: number) => number,
): Map<string, number> {
  const balances = new Map<string, number>();
  for (const a of accounts) balances.set(a.id, a.openingBalance);
  for (const t of txns) {
    for (const [acct, d] of accountDeltas(t, debtsById, round)) {
      balances.set(acct, round((balances.get(acct) ?? 0) + d));
    }
  }
  return balances;
}

export function debtOutstanding(debt: Debt, txns: Txn[], round: (n: number) => number): number {
  const establishing = debt.direction === 'owe' ? 'borrow' : 'lend';
  let total = 0;
  for (const t of txns) {
    for (const l of t.lines) {
      if (l.debtId !== debt.id) continue;
      if (l.type === establishing) total += l.amount;
      else if (l.type === 'repayment') total -= l.amount;
    }
  }
  return round(total);
}

export function debtStatusFrom(debt: Debt, outstanding: number): string {
  if (Math.abs(outstanding) <= 0.005) return 'settled';
  if (debt.status === 'settled') return 'settled';
  return debt.status || 'open';
}

export function dueSettledAmount(due: Due, txns: Txn[], round: (n: number) => number): number {
  let total = 0;
  for (const t of txns) if (t.dueId === due.id) total += Math.abs(t.totalAmount);
  return round(total);
}

export function dueStatusFromSettled(due: Due, settled: number): string {
  if (due.status === 'cancelled') return 'cancelled';
  if (settled <= 0) return 'open';
  if (settled + 0.005 < due.amount) return 'partial';
  return 'settled';
}

/** The financial year a date falls in: "2026-27", or "2026" for a January start. */
export function financialYearOf(date: Date, fyStartMonth: number, timeZone: string): string {
  const { year, month } = localParts(date, timeZone);
  const startYear = month >= fyStartMonth ? year : year - 1;
  if (fyStartMonth === 1) return `${startYear}`;
  return `${startYear}-${String((startYear + 1) % 100).padStart(2, '0')}`;
}

export function contactPosition(
  contactId: string,
  debts: Debt[],
  txns: Txn[],
  round: (n: number) => number,
): { net: number; totalIn: number; totalOut: number } {
  let net = 0;
  for (const d of debts) {
    if (d.contactId !== contactId) continue;
    const o = debtOutstanding(d, txns, round);
    net += d.direction === 'owed' ? o : -o;
  }
  let totalIn = 0;
  let totalOut = 0;
  for (const t of txns) {
    if (t.contactId !== contactId) continue;
    if (t.totalAmount >= 0) totalIn += t.totalAmount;
    else totalOut += -t.totalAmount;
  }
  return { net: round(net), totalIn: round(totalIn), totalOut: round(totalOut) };
}

/** Spend per category in [start, end): expense, interest expense, fee and tax lines. */
export function spendByCategory(txns: Txn[], start: Date, end: Date, round: (n: number) => number) {
  const sums = new Map<string, number>();
  for (const t of txns) {
    if (t.date < start || t.date >= end) continue;
    for (const l of t.lines) {
      if (!isExpenseSpend(l.type) || !l.categoryId) continue;
      sums.set(l.categoryId, round((sums.get(l.categoryId) ?? 0) + l.amount));
    }
  }
  return sums;
}

// ---- dates -----------------------------------------------------------------

export function localParts(date: Date, timeZone: string) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const get = (t: string) => Number(parts.find((p) => p.type === t)!.value);
  return { year: get('year'), month: get('month'), day: get('day') };
}

/** "2026-11-20" in [timeZone] as YYYY-MM-DD. */
export function localDate(date: Date, timeZone: string): string {
  const { year, month, day } = localParts(date, timeZone);
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

/**
 * The instant a caller means. A bare date is midnight in [timeZone], which is
 * how the app stores a date picked on the phone; anything with a time is
 * taken as written.
 */
export function parseWhen(input: string | undefined, timeZone: string, fallback = new Date()): Date {
  if (!input) return fallback;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(input.trim());
  if (m) {
    const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
    // Find the UTC instant whose local date in timeZone is y-mo-d at 00:00.
    const guess = Date.UTC(y, mo - 1, d);
    const offset = tzOffsetMinutes(new Date(guess), timeZone);
    return new Date(guess - offset * 60_000);
  }
  const t = new Date(input);
  if (Number.isNaN(t.getTime())) throw new Error(`Not a date: ${input}`);
  return t;
}

function tzOffsetMinutes(at: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).formatToParts(at);
  const get = (t: string) => Number(parts.find((p) => p.type === t)!.value);
  const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'));
  return Math.round((asUtc - at.getTime()) / 60_000);
}

/** [start, end) of the month or financial year containing [at], in [timeZone]. */
export function periodRange(kind: 'monthly' | 'yearly', at: Date, fyStartMonth: number, timeZone: string) {
  const { year, month } = localParts(at, timeZone);
  const iso = (y: number, m: number) => {
    const yy = y + Math.floor((m - 1) / 12);
    const mm = ((m - 1) % 12) + 1;
    return `${yy}-${String(mm).padStart(2, '0')}-01`;
  };
  if (kind === 'monthly') {
    return { start: parseWhen(iso(year, month), timeZone), end: parseWhen(iso(year, month + 1), timeZone) };
  }
  const startYear = month >= fyStartMonth ? year : year - 1;
  return {
    start: parseWhen(iso(startYear, fyStartMonth), timeZone),
    end: parseWhen(iso(startYear + 1, fyStartMonth), timeZone),
  };
}
