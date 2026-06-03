// Derived calculations (§1 "derived-not-stored"). Everything here is computed
// from transaction lines + entities, never persisted.

import type {
  Account,
  Category,
  Debt,
  Due,
  Transaction,
  TransactionLine,
} from "@/types/models";
import { accountDeltas, roundMoney } from "./txn";
import { financialYearOf, financialYearRange } from "./financialYear";

export function toDate(ts: { toDate?: () => Date } | Date | undefined): Date {
  if (!ts) return new Date(0);
  if (ts instanceof Date) return ts;
  return ts.toDate ? ts.toDate() : new Date(0);
}

/**
 * Chronological comparator for transactions: by the user-picked `date` first,
 * then — for same-date entries — by the full `createdAt` timestamp. Ascending
 * (oldest first); negate for newest-first.
 */
export function compareTxnChrono(
  a: { date: Parameters<typeof toDate>[0]; createdAt?: Parameters<typeof toDate>[0] },
  b: { date: Parameters<typeof toDate>[0]; createdAt?: Parameters<typeof toDate>[0] },
): number {
  const da = toDate(a.date).getTime();
  const db = toDate(b.date).getTime();
  if (da !== db) return da - db;
  const ca = a.createdAt ? toDate(a.createdAt).getTime() : 0;
  const cb = b.createdAt ? toDate(b.createdAt).getTime() : 0;
  return ca - cb;
}

// ---- account balances ------------------------------------------------------

export function accountBalances(
  accounts: Account[],
  txns: Transaction[],
  debtsById: Record<string, Debt>,
): Record<string, number> {
  const balances: Record<string, number> = {};
  for (const a of accounts) balances[a.id] = a.openingBalance;
  for (const txn of txns) {
    const deltas = accountDeltas(txn, debtsById);
    for (const [acctId, delta] of Object.entries(deltas)) {
      balances[acctId] = roundMoney((balances[acctId] ?? 0) + delta);
    }
  }
  return balances;
}

// ---- debt outstanding ------------------------------------------------------
// Outstanding = establishing lines (borrow for "owe", lend for "owed") minus
// repayments, summed over all lines linked to the debt.

function eachLine(txns: Transaction[]): Array<{ txn: Transaction; line: TransactionLine }> {
  const out: Array<{ txn: Transaction; line: TransactionLine }> = [];
  for (const txn of txns) for (const line of txn.lines) out.push({ txn, line });
  return out;
}

export function debtOutstanding(debt: Debt, txns: Transaction[]): number {
  const establishing = debt.direction === "owe" ? "borrow" : "lend";
  let total = 0;
  for (const { line } of eachLine(txns)) {
    if (line.debtId !== debt.id) continue;
    if (line.type === establishing) total += line.amount;
    else if (line.type === "repayment") total -= line.amount;
  }
  return roundMoney(total);
}

export function debtOutstandingMap(
  debts: Debt[],
  txns: Transaction[],
): Record<string, number> {
  const map: Record<string, number> = {};
  for (const d of debts) map[d.id] = debtOutstanding(d, txns);
  return map;
}

// ---- contact net position --------------------------------------------------
// Positive = they owe you (show green), negative = you owe them (show red).

export interface ContactPosition {
  net: number;
  totalIn: number; // money received in txns linked to this contact
  totalOut: number; // money paid out in txns linked to this contact
}

export function contactPosition(
  contactId: string,
  debts: Debt[],
  txns: Transaction[],
): ContactPosition {
  let net = 0;
  for (const debt of debts) {
    if (debt.contactId !== contactId) continue;
    const outstanding = debtOutstanding(debt, txns);
    net += debt.direction === "owed" ? outstanding : -outstanding;
  }

  let totalIn = 0;
  let totalOut = 0;
  for (const txn of txns) {
    if (txn.contactId !== contactId) continue;
    if (txn.totalAmount >= 0) totalIn += txn.totalAmount;
    else totalOut += -txn.totalAmount;
  }

  return {
    net: roundMoney(net),
    totalIn: roundMoney(totalIn),
    totalOut: roundMoney(totalOut),
  };
}

// ---- due settlement --------------------------------------------------------

export function dueSettledAmount(due: Due, txns: Transaction[]): number {
  let total = 0;
  for (const txn of txns) {
    if (txn.dueId !== due.id) continue;
    total += Math.abs(txn.totalAmount);
  }
  return roundMoney(total);
}

export function dueStatusFromSettled(due: Due, settled: number): Due["status"] {
  if (due.status === "cancelled") return "cancelled";
  if (settled <= 0) return "open";
  if (settled + 0.005 < due.amount) return "partial";
  return "settled";
}

// ---- spend by category (within a financial year) ---------------------------

export interface CategorySpend {
  categoryId: string;
  name: string;
  amount: number;
}

// ---- budgets ---------------------------------------------------------------
// Spend per category within an arbitrary [start, end) window (expense lines).
export function categorySpendInRange(
  txns: Transaction[],
  start: Date,
  end: Date,
): Record<string, number> {
  const totals: Record<string, number> = {};
  for (const txn of txns) {
    const d = toDate(txn.date);
    if (d < start || d >= end) continue;
    for (const line of txn.lines) {
      const isExpense =
        line.type === "expense" ||
        line.type === "interest_expense" ||
        line.type === "fee" ||
        line.type === "tax";
      if (!isExpense || !line.categoryId) continue;
      totals[line.categoryId] = roundMoney((totals[line.categoryId] ?? 0) + line.amount);
    }
  }
  return totals;
}

export type BudgetPeriod = "monthly" | "yearly";

export interface BudgetProgress {
  budgetId: string;
  categoryId: string;
  categoryName: string;
  period: BudgetPeriod;
  periodLabel: string; // e.g. "May 2026" or "FY 2026-27"
  limit: number;
  spent: number;
  remaining: number;
  ratio: number; // spent / limit (0..n)
  over: boolean;
}

const MONTH_FMT = new Intl.DateTimeFormat("en-IN", { month: "long", year: "numeric" });

/** The active [start, end) window + a human label for a budget period. */
export function budgetWindow(
  period: BudgetPeriod,
  fyStartMonth: number,
  now: Date = new Date(),
): { start: Date; end: Date; label: string } {
  if (period === "yearly") {
    const { start, end } = financialYearRange(now, fyStartMonth);
    const fy = financialYearOf(now, fyStartMonth);
    return { start, end, label: fyStartMonth === 1 ? fy : `FY ${fy}` };
  }
  const start = new Date(now.getFullYear(), now.getMonth(), 1);
  const end = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  return { start, end, label: MONTH_FMT.format(now) };
}

/**
 * Budget vs actual for the active period of each budget. Spend is derived from
 * expense lines dated within that budget's window (calendar month for monthly,
 * financial year for yearly).
 */
export function budgetProgress(
  budgets: { id: string; categoryId: string; amount: number; period?: BudgetPeriod }[],
  txns: Transaction[],
  categoriesById: Record<string, { name: string }>,
  fyStartMonth = 4,
  now: Date = new Date(),
): BudgetProgress[] {
  // Window depends only on period — compute once per distinct period.
  const windows: Record<BudgetPeriod, ReturnType<typeof budgetWindow>> = {
    monthly: budgetWindow("monthly", fyStartMonth, now),
    yearly: budgetWindow("yearly", fyStartMonth, now),
  };
  const spendByCat: Record<BudgetPeriod, Record<string, number>> = {
    monthly: categorySpendInRange(txns, windows.monthly.start, windows.monthly.end),
    yearly: categorySpendInRange(txns, windows.yearly.start, windows.yearly.end),
  };

  return budgets
    .map((b) => {
      const period: BudgetPeriod = b.period ?? "monthly";
      const spent = spendByCat[period][b.categoryId] ?? 0;
      const limit = b.amount;
      return {
        budgetId: b.id,
        categoryId: b.categoryId,
        categoryName: categoriesById[b.categoryId]?.name ?? "Uncategorized",
        period,
        periodLabel: windows[period].label,
        limit,
        spent: roundMoney(spent),
        remaining: roundMoney(limit - spent),
        ratio: limit > 0 ? spent / limit : 0,
        over: spent > limit + 0.005,
      };
    })
    .sort((a, b) => b.ratio - a.ratio);
}

// ---- shared ledger (cross-user) --------------------------------------------
// Balances are derived from AGREED shared entries (status "accepted"), plus the
// creator's side of still-pending EXPENSES (the creator already paid, so the
// claim stands until rejected). A rejected entry contributes nothing.
//
// Each entry is bilateral: `payerUid` fronted `amount` for `counterpartyUid`
// (an expense), or paid `counterpartyUid`/was the creator of a settlement.
// We compute, from MY perspective, a net per counterparty:
//   net > 0  => they owe me; net < 0 => I owe them.
// "settlement" entries move money the opposite way to an expense.

export interface SharedEntryLike {
  kind: "expense" | "settlement";
  creatorUid: string;
  counterpartyUid: string;
  payerUid: string;
  amount: number;
  status: "pending" | "accepted" | "rejected";
  names: Record<string, string>;
}

export interface SharedBalance {
  uid: string; // the counterparty (from my perspective)
  name: string;
  net: number; // > 0 they owe me; < 0 I owe them
}

/**
 * Net shared balance per counterparty, from `myUid`'s perspective. An entry
 * counts when accepted, or when it's my own still-pending expense claim
 * (I paid; awaiting their response — but my money already moved).
 */
export function sharedBalances(myUid: string, entries: SharedEntryLike[]): SharedBalance[] {
  const net = new Map<string, number>();
  const name = new Map<string, string>();

  for (const e of entries) {
    if (e.status === "rejected") continue;
    // Pending entries only count on the side that already moved money: the
    // creator of an expense, or the payer of a settlement (also the creator).
    if (e.status === "pending" && e.creatorUid !== myUid) continue;

    const other = e.creatorUid === myUid ? e.counterpartyUid : e.creatorUid;
    name.set(other, e.names[other] ?? other);

    // Signed amount in MY favour (+ = they owe me more). In both an expense
    // (payer fronts money the other owes back) and a settlement (payer pays
    // down what they owe), the party who paid moves the balance in their own
    // favour, so the sign is the same: + if I paid, − if I received.
    const delta = e.payerUid === myUid ? e.amount : -e.amount;
    net.set(other, (net.get(other) ?? 0) + delta);
  }

  return [...net.entries()]
    .map(([uid, n]) => ({ uid, name: name.get(uid) ?? uid, net: roundMoney(n) }))
    .filter((b) => Math.abs(b.net) > 0.005)
    .sort((a, b) => b.net - a.net);
}

export interface DebtTransfer {
  fromUid: string;
  fromName: string;
  toUid: string;
  toName: string;
  amount: number;
}

/**
 * Bilateral "who pays whom" list from my perspective. Because the ledger is
 * pairwise (no multi-party netting needed), each non-zero balance is one
 * transfer: I owe them, or they owe me.
 */
export function settleUpTransfers(myUid: string, balances: SharedBalance[]): DebtTransfer[] {
  const meName = "You";
  return balances
    .filter((b) => Math.abs(b.net) > 0.005)
    .map((b) =>
      b.net > 0
        ? { fromUid: b.uid, fromName: b.name, toUid: myUid, toName: meName, amount: b.net }
        : { fromUid: myUid, fromName: meName, toUid: b.uid, toName: b.name, amount: -b.net },
    );
}

export function spendByCategory(
  txns: Transaction[],
  categories: Category[],
  fy: string,
  fyStartMonth: number,
): CategorySpend[] {
  const nameById = new Map(categories.map((c) => [c.id, c.name]));
  const totals = new Map<string, number>();
  for (const txn of txns) {
    if (financialYearOf(toDate(txn.date), fyStartMonth) !== fy) continue;
    for (const line of txn.lines) {
      const isExpense =
        line.type === "expense" ||
        line.type === "interest_expense" ||
        line.type === "fee" ||
        line.type === "tax";
      if (!isExpense || !line.categoryId) continue;
      totals.set(line.categoryId, (totals.get(line.categoryId) ?? 0) + line.amount);
    }
  }
  return [...totals.entries()]
    .map(([categoryId, amount]) => ({
      categoryId,
      name: nameById.get(categoryId) ?? "Uncategorized",
      amount: roundMoney(amount),
    }))
    .sort((a, b) => b.amount - a.amount);
}

/**
 * Spend per category within an arbitrary [start, end) window — the range-based
 * sibling of spendByCategory (which is FY-scoped). Lets the dashboard's
 * spend-by-category card follow the period dropdown. Reuses categorySpendInRange.
 */
export function spendByCategoryInRange(
  txns: Transaction[],
  categories: Category[],
  start: Date,
  end: Date,
): CategorySpend[] {
  const nameById = new Map(categories.map((c) => [c.id, c.name]));
  const totals = categorySpendInRange(txns, start, end);
  return Object.entries(totals)
    .map(([categoryId, amount]) => ({
      categoryId,
      name: nameById.get(categoryId) ?? "Uncategorized",
      amount: roundMoney(amount),
    }))
    .sort((a, b) => b.amount - a.amount);
}

// ---- income / expense / net (within a financial year or month) -------------

export interface PeriodTotals {
  income: number;
  expense: number;
  net: number;
}

export function periodTotals(
  txns: Transaction[],
  predicate: (date: Date) => boolean,
): PeriodTotals {
  let income = 0;
  let expense = 0;
  for (const txn of txns) {
    if (!predicate(toDate(txn.date))) continue;
    for (const line of txn.lines) {
      switch (line.type) {
        case "income":
        case "interest_income":
          income += line.amount;
          break;
        case "expense":
        case "interest_expense":
        case "fee":
        case "tax":
          expense += line.amount;
          break;
        // borrow/lend/repayment/transfers are excluded from income/expense
        default:
          break;
      }
    }
  }
  return {
    income: roundMoney(income),
    expense: roundMoney(expense),
    net: roundMoney(income - expense),
  };
}

// ---- "held for others" (custodial) -----------------------------------------

export function custodialHeld(debts: Debt[], txns: Transaction[]): number {
  let total = 0;
  for (const debt of debts) {
    if (debt.purpose !== "custodial_savings") continue;
    if (debt.direction !== "owe") continue;
    total += debtOutstanding(debt, txns);
  }
  return roundMoney(total);
}

// ---- FY tax summary (§6.9) -------------------------------------------------
// Sums taxable lines by head + total TDS. Auto-excludes debts/transfers because
// those line types never carry a `tax` block.

export interface TaxHeadSummary {
  head: string;
  taxableAmount: number;
  tdsAmount: number;
  lineCount: number;
}

export function fyTaxSummary(
  txns: Transaction[],
  fy: string,
  fyStartMonth: number,
): { byHead: TaxHeadSummary[]; totalTaxable: number; totalTds: number } {
  const heads = new Map<string, TaxHeadSummary>();
  let totalTaxable = 0;
  let totalTds = 0;

  for (const txn of txns) {
    if (financialYearOf(toDate(txn.date), fyStartMonth) !== fy) continue;
    for (const line of txn.lines) {
      const tax = line.tax;
      if (!tax || !tax.taxable) continue;
      const key = tax.head;
      const existing =
        heads.get(key) ?? { head: key, taxableAmount: 0, tdsAmount: 0, lineCount: 0 };
      existing.taxableAmount = roundMoney(existing.taxableAmount + line.amount);
      existing.tdsAmount = roundMoney(existing.tdsAmount + (tax.tdsAmount ?? 0));
      existing.lineCount += 1;
      heads.set(key, existing);
      totalTaxable += line.amount;
      totalTds += tax.tdsAmount ?? 0;
    }
  }

  return {
    byHead: [...heads.values()].sort((a, b) => b.taxableAmount - a.taxableAmount),
    totalTaxable: roundMoney(totalTaxable),
    totalTds: roundMoney(totalTds),
  };
}

// ---- net worth over time ---------------------------------------------------
// Month-end snapshots of net worth across a range. Net worth = total in
// accounts (opening balances + applied deltas) minus payables (debts you owe)
// plus receivables (debts owed to you). Transfers and debt principal movements
// are self-cancelling, so the curve effectively tracks cumulative income−expense
// on top of the starting position — but we compute it directly for correctness.

export interface NetWorthPoint {
  label: string;
  netWorth: number;
}

const monthShort = (d: Date) => d.toLocaleString("en-IN", { month: "short" });

export function netWorthSeries(
  accounts: Account[],
  debts: Debt[],
  txns: Transaction[],
  start: Date,
  end: Date,
): NetWorthPoint[] {
  const debtsById: Record<string, Debt> = {};
  for (const d of debts) debtsById[d.id] = d;
  const sorted = [...txns].sort(
    (a, b) => toDate(a.date).getTime() - toDate(b.date).getTime(),
  );

  const points: NetWorthPoint[] = [];
  let accountsTotal = accounts.reduce((s, a) => s + a.openingBalance, 0);
  const debtOut: Record<string, number> = {};
  let idx = 0;

  const cursor = new Date(start.getFullYear(), start.getMonth(), 1);
  while (cursor < end) {
    const cutoff = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1);
    // Fold in every transaction dated before this month's end.
    while (idx < sorted.length && toDate(sorted[idx].date) < cutoff) {
      const txn = sorted[idx];
      for (const v of Object.values(accountDeltas(txn, debtsById))) accountsTotal += v;
      for (const line of txn.lines) {
        if (!line.debtId) continue;
        const debt = debtsById[line.debtId];
        if (!debt) continue;
        const establishing = debt.direction === "owe" ? "borrow" : "lend";
        if (line.type === establishing)
          debtOut[line.debtId] = (debtOut[line.debtId] ?? 0) + line.amount;
        else if (line.type === "repayment")
          debtOut[line.debtId] = (debtOut[line.debtId] ?? 0) - line.amount;
      }
      idx++;
    }
    let payables = 0;
    let receivables = 0;
    for (const d of debts) {
      const o = debtOut[d.id] ?? 0;
      if (d.direction === "owe") payables += o;
      else receivables += o;
    }
    points.push({
      label: monthShort(cursor),
      netWorth: roundMoney(accountsTotal - payables + receivables),
    });
    cursor.setMonth(cursor.getMonth() + 1);
  }
  return points;
}

// ---- category trend (stacked) ----------------------------------------------
// Per-month expense split across the top categories within a range. Categories
// beyond `topN` are folded into "Other" so the stack stays readable. Returns the
// bucket rows (label + one numeric field per series key) and the ordered keys.

export interface CategoryTrend {
  buckets: Array<Record<string, number | string>>;
  keys: string[];
}

export function categoryTrendSeries(
  txns: Transaction[],
  categories: Category[],
  start: Date,
  end: Date,
  topN = 5,
): CategoryTrend {
  const nameById = new Map(categories.map((c) => [c.id, c.name]));

  // Overall spend per category to decide the top-N.
  const overall = new Map<string, number>();
  for (const txn of txns) {
    const d = toDate(txn.date);
    if (d < start || d >= end) continue;
    for (const line of txn.lines) {
      if (lineIsExpense(line.type) && line.categoryId)
        overall.set(line.categoryId, (overall.get(line.categoryId) ?? 0) + line.amount);
    }
  }
  const ranked = [...overall.entries()].sort((a, b) => b[1] - a[1]);
  const topIds = new Set(ranked.slice(0, topN).map(([id]) => id));
  const hasOther = ranked.length > topN;
  const keys = [
    ...ranked.slice(0, topN).map(([id]) => nameById.get(id) ?? "Uncategorized"),
    ...(hasOther ? ["Other"] : []),
  ];

  // Month buckets.
  const buckets: Array<Record<string, number | string>> = [];
  const index = new Map<string, number>();
  const cursor = new Date(start.getFullYear(), start.getMonth(), 1);
  while (cursor < end) {
    const row: Record<string, number | string> = { label: monthShort(cursor) };
    for (const k of keys) row[k] = 0;
    index.set(`${cursor.getFullYear()}-${cursor.getMonth()}`, buckets.length);
    buckets.push(row);
    cursor.setMonth(cursor.getMonth() + 1);
  }

  for (const txn of txns) {
    const d = toDate(txn.date);
    if (d < start || d >= end) continue;
    const bi = index.get(`${d.getFullYear()}-${d.getMonth()}`);
    if (bi == null) continue;
    for (const line of txn.lines) {
      if (!lineIsExpense(line.type) || !line.categoryId) continue;
      const key =
        topIds.has(line.categoryId)
          ? (nameById.get(line.categoryId) ?? "Uncategorized")
          : hasOther
            ? "Other"
            : null;
      if (key == null) continue;
      buckets[bi][key] = ((buckets[bi][key] as number) ?? 0) + line.amount;
    }
  }
  for (const row of buckets)
    for (const k of keys) row[k] = roundMoney(row[k] as number);

  return { buckets, keys };
}

function lineIsExpense(type: TransactionLine["type"]): boolean {
  return (
    type === "expense" ||
    type === "interest_expense" ||
    type === "fee" ||
    type === "tax"
  );
}

// ---- top movers (category deltas between two FYs) --------------------------
// Compares per-category spend across two CategorySpend lists and returns the
// largest absolute changes, newest period vs the comparison period.

export interface CategoryMover {
  categoryId: string;
  name: string;
  current: number;
  previous: number;
  delta: number;
}

export function topMovers(
  current: CategorySpend[],
  previous: CategorySpend[],
  limit = 5,
): CategoryMover[] {
  const prevById = new Map(previous.map((c) => [c.categoryId, c]));
  const seen = new Set<string>();
  const movers: CategoryMover[] = [];

  for (const c of current) {
    seen.add(c.categoryId);
    const prev = prevById.get(c.categoryId)?.amount ?? 0;
    movers.push({
      categoryId: c.categoryId,
      name: c.name,
      current: c.amount,
      previous: prev,
      delta: roundMoney(c.amount - prev),
    });
  }
  // Categories present last period but gone this period (full drop).
  for (const c of previous) {
    if (seen.has(c.categoryId)) continue;
    movers.push({
      categoryId: c.categoryId,
      name: c.name,
      current: 0,
      previous: c.amount,
      delta: roundMoney(-c.amount),
    });
  }

  return movers
    .filter((m) => m.delta !== 0)
    .sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta))
    .slice(0, limit);
}
