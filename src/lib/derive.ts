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

// ---- shared expenses / member settlement -----------------------------------
// For each shared expense (or settlement), the payer fronts `amount` and each
// participant is responsible for their `share`. A member's net position is:
//   net = (total they paid) - (total of their shares)
// net > 0  => the group owes them; net < 0 => they owe the group.
export interface MemberBalance {
  uid: string;
  name: string;
  net: number;
}

export function memberBalances(
  expenses: {
    amount: number;
    paidBy: string;
    paidByName: string;
    splits: { uid: string; name: string; share: number }[];
  }[],
): MemberBalance[] {
  const net = new Map<string, number>();
  const name = new Map<string, string>();
  for (const e of expenses) {
    net.set(e.paidBy, (net.get(e.paidBy) ?? 0) + e.amount);
    if (e.paidByName) name.set(e.paidBy, e.paidByName);
    for (const s of e.splits) {
      net.set(s.uid, (net.get(s.uid) ?? 0) - s.share);
      if (s.name) name.set(s.uid, s.name);
    }
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
 * Minimal set of "X pays Y ₹Z" transfers that settles all balances. Greedy:
 * repeatedly match the largest debtor against the largest creditor.
 */
export function simplifyDebts(balances: MemberBalance[]): DebtTransfer[] {
  const creditors = balances.filter((b) => b.net > 0.005).map((b) => ({ ...b }));
  const debtors = balances.filter((b) => b.net < -0.005).map((b) => ({ ...b, net: -b.net }));
  creditors.sort((a, b) => b.net - a.net);
  debtors.sort((a, b) => b.net - a.net);

  const transfers: DebtTransfer[] = [];
  let ci = 0;
  let di = 0;
  while (ci < creditors.length && di < debtors.length) {
    const c = creditors[ci];
    const d = debtors[di];
    const amount = roundMoney(Math.min(c.net, d.net));
    if (amount > 0.005) {
      transfers.push({
        fromUid: d.uid,
        fromName: d.name,
        toUid: c.uid,
        toName: c.name,
        amount,
      });
    }
    c.net = roundMoney(c.net - amount);
    d.net = roundMoney(d.net - amount);
    if (c.net <= 0.005) ci++;
    if (d.net <= 0.005) di++;
  }
  return transfers;
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
