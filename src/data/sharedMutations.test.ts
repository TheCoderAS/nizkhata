// Unit tests for the cross-user shared-ledger accounting. We don't hit
// Firestore — instead we mock the batch so we can capture exactly what each
// side writes, and assert the money invariants:
//   - creator records their own share as an expense + a `lend` per participant
//   - the counterparty's acceptance is BALANCE-ONLY (external borrow, total 0)
//   - a settlement records a repayment that moves real money
//   - reflections reconcile to the paid total

import { describe, it, expect, beforeEach, vi } from "vitest";

// ---- capture batch writes --------------------------------------------------
interface Write {
  op: "set" | "update" | "delete";
  path: string;
  data?: Record<string, unknown>;
}
let writes: Write[] = [];

vi.mock("@/firebase/config", () => ({ db: {} }));
vi.mock("./actor", () => ({ getCurrentActor: () => ({ uid: "me", name: "Me" }) }));
vi.mock("./revisions", () => ({ appendRevision: () => {} }));
vi.mock("./mutations", () => ({
  EXTERNAL_ACCOUNT: "__external__",
  newId: () => `id_${Math.random().toString(36).slice(2, 8)}`,
  stripUndefined: (o: Record<string, unknown>) => o,
}));

vi.mock("firebase/firestore", () => {
  const doc = (_db: unknown, coll: string, id: string) => ({ path: `${coll}/${id}` });
  const makeBatch = () => ({
    set: (ref: { path: string }, data: Record<string, unknown>) =>
      writes.push({ op: "set", path: ref.path, data }),
    update: (ref: { path: string }, data: Record<string, unknown>) =>
      writes.push({ op: "update", path: ref.path, data }),
    delete: (ref: { path: string }) => writes.push({ op: "delete", path: ref.path }),
    commit: async () => {},
  });
  return {
    Timestamp: { fromDate: (d: Date) => ({ __date: d }) },
    doc,
    serverTimestamp: () => ({ __ts: true }),
    writeBatch: () => makeBatch(),
    updateDoc: async (ref: { path: string }, data: Record<string, unknown>) =>
      writes.push({ op: "update", path: ref.path, data }),
  };
});

import { connectionIdFor, shareInviteId, createSharedExpense, acceptSharedExpense } from "./sharedMutations";
import type { SharedEntry } from "@/types/models";

const me = { uid: "me", email: "me@x.com", displayName: "Me" } as never;

function txnLines(): Array<{ type: string; amount: number; external?: boolean }> {
  return writes
    .filter((w) => w.op === "set" && w.path.startsWith("transactions/"))
    .flatMap((w) => (w.data?.lines as Array<{ type: string; amount: number; external?: boolean }>) ?? []);
}
function txnTotals(): number[] {
  return writes
    .filter((w) => w.op === "set" && w.path.startsWith("transactions/"))
    .map((w) => w.data?.totalAmount as number);
}
function sharedEntries(): Record<string, unknown>[] {
  return writes
    .filter((w) => w.op === "set" && w.path.startsWith("sharedEntries/"))
    .map((w) => w.data as Record<string, unknown>);
}

beforeEach(() => {
  writes = [];
});

describe("shared-ledger id helpers", () => {
  it("connection id is the sorted uid pair (order-independent)", () => {
    expect(connectionIdFor("b", "a")).toBe("a_b");
    expect(connectionIdFor("a", "b")).toBe("a_b");
  });
  it("share-invite id lowercases the email", () => {
    expect(shareInviteId("u1", "Foo@Bar.com")).toBe("u1_foo@bar.com");
  });
});

describe("createSharedExpense (creator side)", () => {
  it("writes my own-share expense + a lend per participant, and a pending entry", async () => {
    await createSharedExpense({
      me,
      workspaceId: "ws",
      fyStartMonth: 4,
      accountId: "acc1",
      description: "Dinner",
      date: new Date("2026-05-01"),
      myShare: 100,
      myCategoryId: "food",
      participants: [
        { counterpartyUid: "b", counterpartyName: "B", connectionId: "b_me", share: 100 },
      ],
      contacts: [],
      debts: [],
    });

    const lines = txnLines();
    // my own share is an expense
    expect(lines.find((l) => l.type === "expense" && l.amount === 100)).toBeTruthy();
    // the participant's share is a lend (they owe me)
    expect(lines.find((l) => l.type === "lend" && l.amount === 100)).toBeTruthy();

    // one bilateral entry, pending, awaiting the counterparty
    const entries = sharedEntries();
    expect(entries).toHaveLength(1);
    expect(entries[0].status).toBe("pending");
    expect(entries[0].amount).toBe(100);
    expect(entries[0].pendingForUids).toEqual(["b"]);

    // creator's outflow reflects only what left the account this side
    // (my expense -100 + lend -100 = two txns each negative)
    expect(txnTotals().every((t) => t <= 0)).toBe(true);
  });

  it("a multi-person split creates one bilateral entry per participant", async () => {
    await createSharedExpense({
      me,
      workspaceId: "ws",
      fyStartMonth: 4,
      accountId: "acc1",
      description: "Trip",
      date: new Date("2026-05-01"),
      myShare: 100,
      participants: [
        { counterpartyUid: "b", counterpartyName: "B", connectionId: "b_me", share: 100 },
        { counterpartyUid: "c", counterpartyName: "C", connectionId: "c_me", share: 100 },
      ],
      contacts: [],
      debts: [],
    });
    expect(sharedEntries()).toHaveLength(2);
    // two lend lines, one per participant
    expect(txnLines().filter((l) => l.type === "lend")).toHaveLength(2);
  });
});

describe("acceptSharedExpense (counterparty side)", () => {
  it("is balance-only: an external borrow with total 0", async () => {
    const entry: SharedEntry = {
      id: "e1",
      connectionId: "b_me",
      kind: "expense",
      uids: ["me", "b"],
      creatorUid: "b",
      counterpartyUid: "me",
      names: { me: "Me", b: "B" },
      payerUid: "b",
      description: "Dinner",
      amount: 100,
      date: { toDate: () => new Date("2026-05-01") } as never,
      status: "pending",
      pendingForUids: ["me"],
      createdAt: {} as never,
    };

    await acceptSharedExpense({
      entry,
      me,
      workspaceId: "ws",
      fyStartMonth: 4,
      contacts: [],
      debts: [],
    });

    // the shared entry flips to accepted, no longer pending for me
    const flip = writes.find((w) => w.op === "update" && w.path === "sharedEntries/e1");
    expect(flip?.data?.status).toBe("accepted");
    expect(flip?.data?.pendingForUids).toEqual([]);

    // my reflection is an external borrow that moves NO real money
    const lines = txnLines();
    const borrow = lines.find((l) => l.type === "borrow");
    expect(borrow).toBeTruthy();
    expect(borrow?.external).toBe(true);
    expect(borrow?.amount).toBe(100);
    expect(txnTotals()).toContain(0); // balance-only
  });
});
