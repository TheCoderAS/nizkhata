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
import { financialYearOf } from "./financialYear";

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
