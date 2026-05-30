import { describe, it, expect } from "vitest";
import {
  accountDeltas,
  computeTotal,
  primaryAccountEffect,
  validateTransaction,
} from "./txn";
import type { Debt, TransactionLine } from "@/types/models";

function line(p: Partial<TransactionLine> & { type: TransactionLine["type"]; amount: number }): TransactionLine {
  return { lineId: Math.random().toString(36).slice(2), ...p };
}

const oweDebt: Debt = {
  id: "d1",
  workspaceId: "w",
  contactId: "c1",
  direction: "owe",
  purpose: "loan",
  principal: 1000,
  status: "open",
  createdAt: {} as never,
};

describe("primaryAccountEffect", () => {
  it("credits income/borrow/interest_income", () => {
    expect(primaryAccountEffect(line({ type: "income", amount: 100 }))).toBe(100);
    expect(primaryAccountEffect(line({ type: "borrow", amount: 50 }))).toBe(50);
    expect(primaryAccountEffect(line({ type: "interest_income", amount: 10 }))).toBe(10);
  });
  it("debits expense/fee/tax/lend/interest_expense", () => {
    expect(primaryAccountEffect(line({ type: "expense", amount: 100 }))).toBe(-100);
    expect(primaryAccountEffect(line({ type: "fee", amount: 30 }))).toBe(-30);
    expect(primaryAccountEffect(line({ type: "tax", amount: 20 }))).toBe(-20);
    expect(primaryAccountEffect(line({ type: "lend", amount: 200 }))).toBe(-200);
  });
  it("repayment of an 'owe' debt debits the account", () => {
    expect(
      primaryAccountEffect(line({ type: "repayment", amount: 800, debtId: "d1" }), oweDebt),
    ).toBe(-800);
  });
  it("repayment of an 'owed' debt credits the account", () => {
    expect(
      primaryAccountEffect(line({ type: "repayment", amount: 800, debtId: "d1" }), {
        ...oweDebt,
        direction: "owed",
      }),
    ).toBe(800);
  });
  it("transfer_in contributes 0 to the primary account", () => {
    expect(primaryAccountEffect(line({ type: "transfer_in", amount: 500, toAccountId: "a2" }))).toBe(0);
  });
});

describe("computeTotal — spec loan-repayment example", () => {
  it("sums to -1000 from the primary account", () => {
    const lines = [
      line({ type: "repayment", amount: 800, debtId: "d1" }),
      line({ type: "interest_expense", amount: 150 }),
      line({ type: "fee", amount: 30 }),
      line({ type: "tax", amount: 20 }),
    ];
    expect(computeTotal(lines, { d1: oweDebt })).toBe(-1000);
  });
});

describe("accountDeltas — self transfer nets to zero across accounts", () => {
  it("debits source, credits destination", () => {
    const deltas = accountDeltas(
      {
        accountId: "a1",
        lines: [
          line({ type: "transfer_out", amount: 5000 }),
          line({ type: "transfer_in", amount: 5000, toAccountId: "a2" }),
        ],
      },
      {},
    );
    expect(deltas["a1"]).toBe(-5000);
    expect(deltas["a2"]).toBe(5000);
  });
});

describe("validateTransaction", () => {
  const base = { accountId: "a1" };

  it("rejects empty line list", () => {
    expect(validateTransaction({ ...base, lines: [] }).length).toBeGreaterThan(0);
  });
  it("requires a contact when a debt line is present", () => {
    const issues = validateTransaction({
      ...base,
      lines: [line({ type: "borrow", amount: 100, debtId: "d1" })],
    });
    expect(issues.some((i) => i.field === "contactId")).toBe(true);
  });
  it("passes a valid borrow with contact + debt", () => {
    const issues = validateTransaction({
      ...base,
      contactId: "c1",
      lines: [line({ type: "borrow", amount: 100, debtId: "d1" })],
    });
    expect(issues).toHaveLength(0);
  });
  it("requires transfer lines to balance", () => {
    const issues = validateTransaction({
      ...base,
      lines: [
        line({ type: "transfer_out", amount: 5000 }),
        line({ type: "transfer_in", amount: 4000, toAccountId: "a2" }),
      ],
    });
    expect(issues.some((i) => i.message.includes("balance"))).toBe(true);
  });
  it("rejects transfer destination equal to source", () => {
    const issues = validateTransaction({
      ...base,
      lines: [
        line({ type: "transfer_out", amount: 100 }),
        line({ type: "transfer_in", amount: 100, toAccountId: "a1" }),
      ],
    });
    expect(issues.some((i) => i.field === "toAccountId")).toBe(true);
  });
  it("flags header total that doesn't reconcile", () => {
    const issues = validateTransaction(
      {
        ...base,
        lines: [line({ type: "expense", amount: 100 })],
        totalAmount: -50,
      },
      {},
    );
    expect(issues.some((i) => i.field === "totalAmount")).toBe(true);
  });
  it("accepts header total that reconciles", () => {
    const issues = validateTransaction(
      {
        ...base,
        lines: [line({ type: "expense", amount: 100 })],
        totalAmount: -100,
      },
      {},
    );
    expect(issues).toHaveLength(0);
  });
});
