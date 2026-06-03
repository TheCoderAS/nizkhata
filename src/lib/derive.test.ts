import { describe, it, expect } from "vitest";
import {
  compareTxnChrono,
  budgetProgress,
  sharedBalances,
  settleUpTransfers,
  netWorthSeries,
  categoryTrendSeries,
  topMovers,
  type SharedEntryLike,
} from "./derive";
import type { Transaction } from "@/types/models";

// Build a bilateral shared entry from A's helper perspective.
function entry(
  partial: Partial<SharedEntryLike> & {
    creatorUid: string;
    counterpartyUid: string;
    amount: number;
  },
): SharedEntryLike {
  return {
    kind: "expense",
    payerUid: partial.creatorUid,
    status: "accepted",
    names: { [partial.creatorUid]: partial.creatorUid, [partial.counterpartyUid]: partial.counterpartyUid },
    ...partial,
  };
}

describe("sharedBalances + settleUpTransfers", () => {
  it("an accepted expense I paid means they owe me", () => {
    const balances = sharedBalances("A", [
      entry({ creatorUid: "A", counterpartyUid: "B", amount: 100, payerUid: "A" }),
    ]);
    expect(balances).toEqual([{ uid: "B", name: "B", net: 100 }]);
    const [t] = settleUpTransfers("A", balances);
    expect(t.fromUid).toBe("B");
    expect(t.toUid).toBe("A");
    expect(t.amount).toBe(100);
  });

  it("my own still-pending expense claim counts (I already paid)", () => {
    const balances = sharedBalances("A", [
      entry({ creatorUid: "A", counterpartyUid: "B", amount: 50, payerUid: "A", status: "pending" }),
    ]);
    expect(balances[0].net).toBe(50);
  });

  it("a pending claim against me does NOT count until I accept", () => {
    const balances = sharedBalances("B", [
      entry({ creatorUid: "A", counterpartyUid: "B", amount: 50, payerUid: "A", status: "pending" }),
    ]);
    expect(balances).toHaveLength(0);
  });

  it("from the counterparty's view an accepted expense means they owe", () => {
    const balances = sharedBalances("B", [
      entry({ creatorUid: "A", counterpartyUid: "B", amount: 80, payerUid: "A" }),
    ]);
    expect(balances).toEqual([{ uid: "A", name: "A", net: -80 }]);
  });

  it("a settlement nets against the expense to zero", () => {
    const balances = sharedBalances("A", [
      entry({ creatorUid: "A", counterpartyUid: "B", amount: 100, payerUid: "A" }),
      // B pays A back 100: a settlement where B is creator+payer.
      entry({
        kind: "settlement",
        creatorUid: "B",
        counterpartyUid: "A",
        amount: 100,
        payerUid: "B",
      }),
    ]);
    expect(balances).toHaveLength(0);
    expect(settleUpTransfers("A", balances)).toHaveLength(0);
  });

  it("rejected entries contribute nothing", () => {
    const balances = sharedBalances("A", [
      entry({ creatorUid: "A", counterpartyUid: "B", amount: 100, payerUid: "A", status: "rejected" }),
    ]);
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

describe("netWorthSeries", () => {
  const accounts = [{ id: "a", openingBalance: 1000 }] as never;
  it("tracks month-end net worth as cumulative income minus expense", () => {
    const txns = [
      txn(day("2026-04-10"), "food", 200), // expense -200
      incomeTxn(day("2026-05-15"), 500), // income +500
    ];
    const series = netWorthSeries(
      accounts,
      [],
      txns,
      new Date(2026, 3, 1),
      new Date(2026, 6, 1),
    );
    expect(series.map((p) => p.netWorth)).toEqual([800, 1300, 1300]);
  });

  it("subtracts payables and adds receivables", () => {
    const debts = [
      { id: "d1", direction: "owe" },
      { id: "d2", direction: "owed" },
    ] as never;
    const txns = [debtTxn(day("2026-04-05"), "d1", "borrow", 300)];
    const series = netWorthSeries(
      accounts,
      debts,
      txns,
      new Date(2026, 3, 1),
      new Date(2026, 4, 1),
    );
    // Borrow adds 300 cash but +300 payable → net worth unchanged at 1000.
    expect(series[0].netWorth).toBe(1000);
  });
});

describe("categoryTrendSeries", () => {
  const cats = [
    { id: "food", name: "Food" },
    { id: "rent", name: "Rent" },
  ] as never;
  it("buckets expense per category per month", () => {
    const txns = [
      txn(day("2026-04-10"), "food", 100),
      txn(day("2026-04-20"), "rent", 500),
      txn(day("2026-05-10"), "food", 150),
    ];
    const { buckets, keys } = categoryTrendSeries(
      txns,
      cats,
      new Date(2026, 3, 1),
      new Date(2026, 5, 1),
    );
    expect(keys).toEqual(["Rent", "Food"]); // ranked by overall spend
    expect(buckets[0]).toMatchObject({ Food: 100, Rent: 500 });
    expect(buckets[1]).toMatchObject({ Food: 150, Rent: 0 });
  });

  it("folds categories beyond topN into Other", () => {
    const many = [
      { id: "c1", name: "C1" },
      { id: "c2", name: "C2" },
    ] as never;
    const txns = [
      txn(day("2026-04-01"), "c1", 100),
      txn(day("2026-04-01"), "c2", 30),
    ];
    const { keys, buckets } = categoryTrendSeries(
      txns,
      many,
      new Date(2026, 3, 1),
      new Date(2026, 4, 1),
      1,
    );
    expect(keys).toEqual(["C1", "Other"]);
    expect(buckets[0]).toMatchObject({ C1: 100, Other: 30 });
  });
});

describe("topMovers", () => {
  it("ranks categories by absolute change, newest vs prior", () => {
    const current = [
      { categoryId: "food", name: "Food", amount: 500 },
      { categoryId: "fuel", name: "Fuel", amount: 100 },
    ];
    const previous = [
      { categoryId: "food", name: "Food", amount: 200 },
      { categoryId: "rent", name: "Rent", amount: 1000 },
    ];
    const movers = topMovers(current, previous, 3);
    expect(movers[0]).toMatchObject({ name: "Rent", delta: -1000 });
    expect(movers[1]).toMatchObject({ name: "Food", delta: 300 });
    expect(movers[2]).toMatchObject({ name: "Fuel", delta: 100 });
  });
});

function incomeTxn(date: Date, amount: number): Transaction {
  return {
    id: Math.random().toString(36).slice(2),
    workspaceId: "w",
    date: date as never,
    accountId: "a",
    totalAmount: amount,
    hasSplit: false,
    financialYear: "2026-27",
    createdBy: { uid: "u", name: "U" },
    createdAt: date as never,
    lines: [{ lineId: "l1", type: "income", amount }],
  } as Transaction;
}

function debtTxn(
  date: Date,
  debtId: string,
  type: "borrow" | "lend" | "repayment",
  amount: number,
): Transaction {
  return {
    id: Math.random().toString(36).slice(2),
    workspaceId: "w",
    date: date as never,
    accountId: "a",
    totalAmount: type === "lend" || type === "repayment" ? -amount : amount,
    hasSplit: false,
    financialYear: "2026-27",
    createdBy: { uid: "u", name: "U" },
    createdAt: date as never,
    lines: [{ lineId: "l1", type, amount, debtId }],
  } as Transaction;
}
