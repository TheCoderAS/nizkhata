import { describe, it, expect } from "vitest";
import { compareTxnChrono, budgetProgress, memberBalances, simplifyDebts } from "./derive";
import type { Transaction } from "@/types/models";

function exp(paidBy: string, amount: number, shares: [string, number][]) {
  return {
    amount,
    paidBy,
    paidByName: paidBy,
    splits: shares.map(([uid, share]) => ({ uid, name: uid, share })),
  };
}

describe("memberBalances + simplifyDebts", () => {
  it("computes net positions for an equal 3-way split", () => {
    // A pays 300, split equally among A, B, C (100 each)
    const balances = memberBalances([exp("A", 300, [["A", 100], ["B", 100], ["C", 100]])]);
    const net = Object.fromEntries(balances.map((b) => [b.uid, b.net]));
    expect(net.A).toBe(200); // paid 300, owes 100 -> +200
    expect(net.B).toBe(-100);
    expect(net.C).toBe(-100);
  });

  it("simplifies to minimal transfers", () => {
    const balances = memberBalances([exp("A", 300, [["A", 100], ["B", 100], ["C", 100]])]);
    const transfers = simplifyDebts(balances);
    expect(transfers).toHaveLength(2);
    for (const t of transfers) {
      expect(t.toUid).toBe("A");
      expect(t.amount).toBe(100);
    }
  });

  it("a settlement cancels the matching debt", () => {
    const expense = exp("A", 200, [["A", 100], ["B", 100]]); // B owes A 100
    const settlement = exp("B", 100, [["A", 100]]); // B pays A 100
    const transfers = simplifyDebts(memberBalances([expense, settlement]));
    expect(transfers).toHaveLength(0); // fully settled
  });

  it("ignores members with a zero net", () => {
    const balances = memberBalances([exp("A", 100, [["A", 100]])]); // A paid own share
    expect(balances).toHaveLength(0);
  });
});

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
  const now = day("2026-05-15");
  const cats = { food: { name: "Food" } };
  const fyStart = 4; // April

  it("monthly: sums this calendar month's expense lines against the limit", () => {
    const txns = [
      txn(day("2026-05-02"), "food", 300),
      txn(day("2026-05-20"), "food", 250),
      txn(day("2026-04-30"), "food", 999), // previous month — excluded
    ];
    const [p] = budgetProgress(
      [{ id: "b", categoryId: "food", amount: 1000, period: "monthly" }],
      txns,
      cats,
      fyStart,
      now,
    );
    expect(p.spent).toBe(550);
    expect(p.remaining).toBe(450);
    expect(p.over).toBe(false);
    expect(p.period).toBe("monthly");
    expect(p.periodLabel).toBe("May 2026");
  });

  it("yearly: sums the financial year (Apr–Mar) against the limit", () => {
    const txns = [
      txn(day("2026-05-02"), "food", 300), // in FY 2026-27
      txn(day("2026-04-01"), "food", 200), // FY start, included
      txn(day("2026-03-31"), "food", 999), // previous FY — excluded
    ];
    const [p] = budgetProgress(
      [{ id: "b", categoryId: "food", amount: 5000, period: "yearly" }],
      txns,
      cats,
      fyStart,
      now,
    );
    expect(p.spent).toBe(500);
    expect(p.period).toBe("yearly");
    expect(p.periodLabel).toBe("FY 2026-27");
  });

  it("flags over-budget", () => {
    const txns = [txn(day("2026-05-10"), "food", 1200)];
    const [p] = budgetProgress(
      [{ id: "b", categoryId: "food", amount: 1000, period: "monthly" }],
      txns,
      cats,
      fyStart,
      now,
    );
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
