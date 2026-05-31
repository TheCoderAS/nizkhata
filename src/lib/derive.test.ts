import { describe, it, expect } from "vitest";
import { compareTxnChrono, budgetProgress } from "./derive";
import type { Transaction } from "@/types/models";

const day = (iso: string) => new Date(iso);

function txn(date: Date, categoryId: string, amount: number): Transaction {
  return {
    id: Math.random().toString(36).slice(2),
    workspaceId: "w",
    date: date as never,
    accountId: "a",
    totalAmount: -amount,
    hasSplit: false,
    financialYear: "2026-27",
    createdBy: { uid: "u", name: "U" },
    createdAt: date as never,
    lines: [{ lineId: "l1", type: "expense", amount, categoryId }],
  } as Transaction;
}

describe("budgetProgress", () => {
  const month = day("2026-05-15");
  const cats = { food: { name: "Food" } };

  it("sums this month's expense lines against the limit", () => {
    const txns = [
      txn(day("2026-05-02"), "food", 300),
      txn(day("2026-05-20"), "food", 250),
      txn(day("2026-04-30"), "food", 999), // previous month — excluded
    ];
    const [p] = budgetProgress([{ id: "b", categoryId: "food", amount: 1000 }], txns, cats, month);
    expect(p.spent).toBe(550);
    expect(p.remaining).toBe(450);
    expect(p.over).toBe(false);
    expect(p.categoryName).toBe("Food");
  });

  it("flags over-budget", () => {
    const txns = [txn(day("2026-05-10"), "food", 1200)];
    const [p] = budgetProgress([{ id: "b", categoryId: "food", amount: 1000 }], txns, cats, month);
    expect(p.over).toBe(true);
    expect(p.remaining).toBe(-200);
  });
});

describe("compareTxnChrono", () => {
  it("orders by date first", () => {
    const a = { date: day("2026-05-01"), createdAt: day("2026-05-10T10:00:00Z") };
    const b = { date: day("2026-05-02"), createdAt: day("2026-05-01T00:00:00Z") };
    expect(compareTxnChrono(a, b)).toBeLessThan(0); // a (earlier date) first
  });

  it("breaks same-date ties by full createdAt timestamp", () => {
    const earlierEntry = {
      date: day("2026-05-01"),
      createdAt: day("2026-05-01T09:00:00Z"),
    };
    const laterEntry = {
      date: day("2026-05-01"),
      createdAt: day("2026-05-03T23:30:00Z"), // entered 2 days later
    };
    expect(compareTxnChrono(earlierEntry, laterEntry)).toBeLessThan(0);
    // newest-first (negated) puts the later-created one on top
    expect(compareTxnChrono(laterEntry, earlierEntry)).toBeGreaterThan(0);
  });

  it("a later date always wins over a late-in-day createdAt on an earlier date", () => {
    const earlierDateLateCreate = {
      date: day("2026-05-01"),
      createdAt: day("2026-05-01T23:59:59Z"),
    };
    const laterDateEarlyCreate = {
      date: day("2026-05-02"),
      createdAt: day("2026-05-02T00:00:01Z"),
    };
    expect(compareTxnChrono(earlierDateLateCreate, laterDateEarlyCreate)).toBeLessThan(0);
  });

  it("treats a missing createdAt as earliest within the day", () => {
    const noCreated = { date: day("2026-05-01") };
    const withCreated = { date: day("2026-05-01"), createdAt: day("2026-05-01T00:00:01Z") };
    expect(compareTxnChrono(noCreated, withCreated)).toBeLessThan(0);
  });
});
