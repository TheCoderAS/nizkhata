// Dashboard period helpers: resolve a named period to a [start, end) range and
// bucket transactions into a trend series of income / expense / net.

import type { Transaction } from "@/types/models";
import { financialYearRange } from "./financialYear";
import { roundMoney } from "./txn";
import { toDate } from "./derive";

export type PeriodKind = "week" | "month" | "year" | "fy" | "custom";

export interface DateRange {
  start: Date;
  end: Date; // exclusive
}

export const PERIOD_LABELS: Record<PeriodKind, string> = {
  week: "This week",
  month: "This month",
  year: "This year",
  fy: "Financial year",
  custom: "Custom range",
};

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

/** Resolve a named period (relative to `now`) to a concrete date range. */
export function resolvePeriod(
  kind: Exclude<PeriodKind, "custom">,
  now: Date,
  fyStartMonth: number,
): DateRange {
  switch (kind) {
    case "week": {
      // week starts Monday
      const day = (now.getDay() + 6) % 7;
      const start = startOfDay(now);
      start.setDate(start.getDate() - day);
      const end = new Date(start);
      end.setDate(end.getDate() + 7);
      return { start, end };
    }
    case "month": {
      const start = new Date(now.getFullYear(), now.getMonth(), 1);
      const end = new Date(now.getFullYear(), now.getMonth() + 1, 1);
      return { start, end };
    }
    case "year": {
      const start = new Date(now.getFullYear(), 0, 1);
      const end = new Date(now.getFullYear() + 1, 0, 1);
      return { start, end };
    }
    case "fy":
      return financialYearRange(now, fyStartMonth);
  }
}

export interface TrendBucket {
  label: string;
  income: number;
  expense: number;
  net: number;
}

export interface TrendResult {
  buckets: TrendBucket[];
  totals: { income: number; expense: number; net: number };
}

function bucketCountAndStep(range: DateRange): {
  unit: "day" | "month";
  // how to label a bucket start
  fmt: (d: Date) => string;
} {
  const days = (range.end.getTime() - range.start.getTime()) / 86400000;
  if (days <= 45) {
    return {
      unit: "day",
      fmt: (d) => `${d.getDate()}/${d.getMonth() + 1}`,
    };
  }
  return {
    unit: "month",
    fmt: (d) => d.toLocaleString("en-IN", { month: "short" }),
  };
}

function lineImpact(type: Transaction["lines"][number]["type"]): "income" | "expense" | null {
  switch (type) {
    case "income":
    case "interest_income":
      return "income";
    case "expense":
    case "interest_expense":
    case "fee":
    case "tax":
      return "expense";
    default:
      return null; // transfers / debt movements excluded
  }
}

/**
 * Bucket transactions in `range` into a trend of income/expense/net. Buckets are
 * daily for short ranges (≤45 days) and monthly otherwise.
 */
export function trendSeries(txns: Transaction[], range: DateRange): TrendResult {
  const { unit, fmt } = bucketCountAndStep(range);

  // build empty buckets across the range
  const buckets: TrendBucket[] = [];
  const index = new Map<string, number>();
  const cursor = new Date(range.start);
  const keyOf = (d: Date) =>
    unit === "day"
      ? `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`
      : `${d.getFullYear()}-${d.getMonth()}`;

  while (cursor < range.end) {
    index.set(keyOf(cursor), buckets.length);
    buckets.push({ label: fmt(cursor), income: 0, expense: 0, net: 0 });
    if (unit === "day") cursor.setDate(cursor.getDate() + 1);
    else cursor.setMonth(cursor.getMonth() + 1);
  }

  let tIncome = 0;
  let tExpense = 0;
  for (const txn of txns) {
    const d = toDate(txn.date);
    if (d < range.start || d >= range.end) continue;
    const bi = index.get(keyOf(d));
    if (bi == null) continue;
    for (const line of txn.lines) {
      const impact = lineImpact(line.type);
      if (impact === "income") {
        buckets[bi].income += line.amount;
        tIncome += line.amount;
      } else if (impact === "expense") {
        buckets[bi].expense += line.amount;
        tExpense += line.amount;
      }
    }
  }

  for (const b of buckets) {
    b.income = roundMoney(b.income);
    b.expense = roundMoney(b.expense);
    b.net = roundMoney(b.income - b.expense);
  }

  return {
    buckets,
    totals: {
      income: roundMoney(tIncome),
      expense: roundMoney(tExpense),
      net: roundMoney(tIncome - tExpense),
    },
  };
}
