// Cross-user shared ledger (Splitwise-style) write helpers.
//
// Unlike `mutations.ts`, these touch collections keyed by user uid rather than
// workspaceId: `shareInvites`, `sharedConnections`, `sharedEntries`. The model
// (agreed with the spec owner):
//
//   - A shared item is strictly BILATERAL (creator ↔ one counterparty). A
//     multi-person split is several bilateral entries created together, so each
//     counterparty consents to their own claim independently.
//   - The creator already paid, so their side records the money movement
//     IMMEDIATELY (a real account-linked transaction). A rejection by the
//     counterparty becomes a conflict the creator resolves (absorb / remove).
//   - The counterparty is BALANCE-ONLY: accepting records an account-less
//     (external) debt that tracks "I owe you" without touching their accounts
//     until an actual settlement moves money.
//   - Each side reflects into ITS OWN workspace only (never the other's), so
//     Security Rules are never crossed. The cross-user `sharedEntries` doc is
//     the consent layer; the local `debts`/`transactions` are each book's
//     private handle, linked back by `sharedEntryId`.
//
// No revision log is written for the cross-user docs themselves (they are not
// workspace entities); the workspace-local reflections are fully audited.

import {
  Timestamp,
  doc,
  serverTimestamp,
  updateDoc,
  writeBatch,
  type WriteBatch,
} from "firebase/firestore";
import type { User as FirebaseUser } from "firebase/auth";
import { db } from "@/firebase/config";
import { financialYearOf } from "@/lib/financialYear";
import { getCurrentActor } from "./actor";
import { appendRevision } from "./revisions";
import { EXTERNAL_ACCOUNT, newId, stripUndefined } from "./mutations";
import type {
  Actor,
  Contact,
  Debt,
  DebtDirection,
  SharedEntry,
  SharedEntryKind,
  TransactionLine,
} from "@/types/models";

// ---- ids -------------------------------------------------------------------

/** Sorted-pair connection id, stable regardless of who initiates. */
export function connectionIdFor(a: string, b: string): string {
  return [a, b].sort().join("_");
}

/** Deterministic share-invite id (mirrors workspace invites). */
export function shareInviteId(fromUid: string, email: string): string {
  return `${fromUid}_${email.toLowerCase()}`;
}

// ---- invites & connections -------------------------------------------------

/** Invite another user (by email) to share. Idempotent on (me, email). */
export async function inviteSharedPartner(
  me: FirebaseUser,
  toEmail: string,
): Promise<string> {
  const email = toEmail.trim().toLowerCase();
  const id = shareInviteId(me.uid, email);
  const expiresAt = Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000));
  await setDocMerge(id, {
    id,
    fromUid: me.uid,
    fromName: actorName(me),
    fromEmail: (me.email ?? "").toLowerCase(),
    toEmail: email,
    status: "pending",
    createdAt: serverTimestamp(),
    expiresAt,
  });
  return id;
}

export async function revokeShareInvite(id: string): Promise<void> {
  await updateDoc(doc(db, "shareInvites", id), { status: "revoked" });
}

async function setDocMerge(id: string, data: Record<string, unknown>): Promise<void> {
  const batch = writeBatch(db);
  batch.set(doc(db, "shareInvites", id), data);
  await batch.commit();
}

function actorName(u: FirebaseUser): string {
  return u.displayName?.trim() || (u.email ? u.email.toLowerCase() : "") || `${u.uid.slice(0, 8)}…`;
}

/**
 * Establish (or refresh) the connection between two users and mark the
 * originating invite accepted. Called at onboarding when the invitee signs in.
 */
export async function acceptShareInvite(
  invite: { id: string; fromUid: string; fromName: string; fromEmail: string },
  me: FirebaseUser,
): Promise<string> {
  const connId = connectionIdFor(invite.fromUid, me.uid);
  const batch = writeBatch(db);
  batch.set(doc(db, "sharedConnections", connId), {
    id: connId,
    uids: [invite.fromUid, me.uid].sort(),
    names: { [invite.fromUid]: invite.fromName, [me.uid]: actorName(me) },
    emails: {
      [invite.fromUid]: invite.fromEmail,
      [me.uid]: (me.email ?? "").toLowerCase(),
    },
    status: "active",
    createdAt: serverTimestamp(),
  });
  batch.set(doc(db, "shareInvites", invite.id), { status: "accepted" }, { merge: true });
  await batch.commit();
  return connId;
}

// ---- local reflection helpers ----------------------------------------------
// Each side mirrors an agreed shared item into its own workspace using the
// normal debt/transaction engine. These find-or-create the local handle
// (a hidden contact tagged with the counterparty's uid) and an aggregate
// "shared" debt per direction, accumulating new docs into the batch.

interface ReflectionCtx {
  workspaceId: string;
  fyStartMonth: number;
  by: Actor;
  contacts: Contact[]; // existing local contacts (for dedupe)
  debts: Debt[]; // existing local debts (for dedupe)
  // docs created earlier in THIS batch, so repeated calls dedupe too
  newContacts: Contact[];
  newDebts: Debt[];
}

function findOrCreateSharedContact(
  batch: WriteBatch,
  ctx: ReflectionCtx,
  connectionUid: string,
  name: string,
): string {
  const hit =
    ctx.contacts.find((c) => c.connectionUid === connectionUid) ??
    ctx.newContacts.find((c) => c.connectionUid === connectionUid);
  if (hit) return hit.id;

  const id = newId("contacts");
  const data = {
    id,
    workspaceId: ctx.workspaceId,
    name,
    type: "person" as const,
    connectionUid,
  };
  batch.set(doc(db, "contacts", id), {
    ...data,
    createdBy: ctx.by,
    createdAt: serverTimestamp(),
    updatedBy: ctx.by,
    updatedAt: serverTimestamp(),
  });
  appendRevision(batch, {
    workspaceId: ctx.workspaceId,
    entityType: "contacts",
    entityId: id,
    action: "create",
    by: ctx.by,
    snapshot: { name, type: "person", connectionUid },
  });
  ctx.newContacts.push(data as Contact);
  return id;
}

function findOrCreateSharedDebt(
  batch: WriteBatch,
  ctx: ReflectionCtx,
  contactId: string,
  direction: DebtDirection,
): string {
  const match = (d: Debt) =>
    d.purpose === "shared" && d.contactId === contactId && d.direction === direction;
  const hit = ctx.debts.find(match) ?? ctx.newDebts.find(match);
  if (hit) return hit.id;

  const id = newId("debts");
  const data = {
    id,
    workspaceId: ctx.workspaceId,
    contactId,
    direction,
    purpose: "shared" as const,
    principal: 0,
    status: "open" as const,
  };
  batch.set(doc(db, "debts", id), {
    ...data,
    createdBy: ctx.by,
    createdAt: serverTimestamp(),
    updatedBy: ctx.by,
    updatedAt: serverTimestamp(),
  });
  appendRevision(batch, {
    workspaceId: ctx.workspaceId,
    entityType: "debts",
    entityId: id,
    action: "create",
    by: ctx.by,
    snapshot: { contactId, direction, purpose: "shared", principal: 0, status: "open" },
  });
  ctx.newDebts.push(data as Debt);
  return id;
}

/** Append a reflection transaction (single line) to the batch. */
function addReflectionTxn(
  batch: WriteBatch,
  ctx: ReflectionCtx,
  params: {
    sharedEntryId: string;
    contactId: string;
    accountId: string; // EXTERNAL_ACCOUNT for balance-only
    line: TransactionLine;
    totalAmount: number;
    date: Date;
    note: string;
  },
): void {
  const id = newId("transactions");
  batch.set(doc(db, "transactions", id), {
    id,
    workspaceId: ctx.workspaceId,
    date: Timestamp.fromDate(params.date),
    accountId: params.accountId,
    contactId: params.contactId,
    sharedEntryId: params.sharedEntryId,
    totalAmount: params.totalAmount,
    hasSplit: false,
    financialYear: financialYearOf(params.date, ctx.fyStartMonth),
    note: params.note,
    createdBy: ctx.by,
    createdAt: serverTimestamp(),
    updatedBy: ctx.by,
    updatedAt: serverTimestamp(),
    lines: [stripUndefined(params.line)],
  });
  appendRevision(batch, {
    workspaceId: ctx.workspaceId,
    entityType: "transactions",
    entityId: id,
    action: "create",
    by: ctx.by,
  });
}

// ---- create a shared expense (creator side) --------------------------------

export interface SharedExpenseParticipant {
  counterpartyUid: string;
  counterpartyName: string;
  connectionId: string;
  share: number; // their portion (> 0)
}

export interface CreateSharedExpenseInput {
  me: FirebaseUser;
  workspaceId: string;
  fyStartMonth: number;
  accountId: string; // the account the creator actually paid from
  description: string;
  date: Date;
  myShare: number; // the creator's own portion (0 if none)
  myCategoryId?: string; // category for the creator's own share
  participants: SharedExpenseParticipant[];
  contacts: Contact[];
  debts: Debt[];
}

/**
 * Record an expense the creator paid and split with one or more counterparties.
 * In a single batch:
 *   - one bilateral `sharedEntry` per counterparty (status "pending"),
 *   - the creator's own-share `expense` transaction (if myShare > 0),
 *   - a `lend` reflection transaction per counterparty (real account; they owe
 *     the creator — an "owed" shared debt).
 */
export async function createSharedExpense(input: CreateSharedExpenseInput): Promise<void> {
  const by = getCurrentActor();
  const batch = writeBatch(db);
  const ctx: ReflectionCtx = {
    workspaceId: input.workspaceId,
    fyStartMonth: input.fyStartMonth,
    by,
    contacts: input.contacts,
    debts: input.debts,
    newContacts: [],
    newDebts: [],
  };

  // Creator's own share is a plain expense (no shared entry, no contact).
  if (input.myShare > 0) {
    const id = newId("transactions");
    batch.set(doc(db, "transactions", id), {
      id,
      workspaceId: input.workspaceId,
      date: Timestamp.fromDate(input.date),
      accountId: input.accountId,
      totalAmount: -input.myShare,
      hasSplit: false,
      financialYear: financialYearOf(input.date, input.fyStartMonth),
      note: `${input.description} (my share)`,
      createdBy: by,
      createdAt: serverTimestamp(),
      updatedBy: by,
      updatedAt: serverTimestamp(),
      lines: [
        stripUndefined({
          lineId: `share_${Date.now()}`,
          type: "expense",
          amount: input.myShare,
          categoryId: input.myCategoryId,
          note: "My share",
        }),
      ],
    });
    appendRevision(batch, {
      workspaceId: input.workspaceId,
      entityType: "transactions",
      entityId: id,
      action: "create",
      by,
    });
  }

  for (const p of input.participants) {
    const entryId = newId("sharedEntries");
    const uids = [input.me.uid, p.counterpartyUid] as [string, string];
    batch.set(doc(db, "sharedEntries", entryId), {
      id: entryId,
      connectionId: p.connectionId,
      kind: "expense" as SharedEntryKind,
      uids,
      creatorUid: input.me.uid,
      counterpartyUid: p.counterpartyUid,
      names: { [input.me.uid]: actorName(input.me), [p.counterpartyUid]: p.counterpartyName },
      payerUid: input.me.uid,
      description: input.description,
      amount: p.share,
      date: Timestamp.fromDate(input.date),
      status: "pending",
      pendingForUids: [p.counterpartyUid],
      createdBy: by,
      createdAt: serverTimestamp(),
      updatedBy: by,
      updatedAt: serverTimestamp(),
    });

    // Reflect: they owe me (an "owed" shared debt); money left my account.
    const contactId = findOrCreateSharedContact(batch, ctx, p.counterpartyUid, p.counterpartyName);
    const debtId = findOrCreateSharedDebt(batch, ctx, contactId, "owed");
    addReflectionTxn(batch, ctx, {
      sharedEntryId: entryId,
      contactId,
      accountId: input.accountId,
      line: {
        lineId: `lend_${entryId}`,
        type: "lend",
        amount: p.share,
        debtId,
        note: input.description,
      },
      totalAmount: -p.share,
      date: input.date,
      note: input.description,
    });
  }

  await batch.commit();
}

// ---- respond to a shared expense (counterparty side) -----------------------

export interface RespondInput {
  entry: SharedEntry;
  me: FirebaseUser;
  workspaceId: string;
  fyStartMonth: number;
  contacts: Contact[];
  debts: Debt[];
  // Only used when accepting a SETTLEMENT (real inflow): the account the money
  // lands in. Omit for balance-only acceptance of an expense.
  accountId?: string;
}

/**
 * Accept a shared expense: flip my consent and record a BALANCE-ONLY debt
 * (external borrow — I owe the creator) that doesn't touch my accounts. The
 * status flip and the local reflection are separate concerns but committed
 * together in one batch.
 */
export async function acceptSharedExpense(input: RespondInput): Promise<void> {
  const by = getCurrentActor();
  const { entry } = input;
  const batch = writeBatch(db);

  batch.update(doc(db, "sharedEntries", entry.id), {
    status: "accepted",
    pendingForUids: [],
    updatedBy: by,
    updatedAt: serverTimestamp(),
  });

  const ctx: ReflectionCtx = {
    workspaceId: input.workspaceId,
    fyStartMonth: input.fyStartMonth,
    by,
    contacts: input.contacts,
    debts: input.debts,
    newContacts: [],
    newDebts: [],
  };
  const creatorName = entry.names[entry.creatorUid] ?? "Partner";
  const contactId = findOrCreateSharedContact(batch, ctx, entry.creatorUid, creatorName);
  const debtId = findOrCreateSharedDebt(batch, ctx, contactId, "owe");
  addReflectionTxn(batch, ctx, {
    sharedEntryId: entry.id,
    contactId,
    accountId: EXTERNAL_ACCOUNT, // balance-only until I actually settle
    line: {
      lineId: `borrow_${entry.id}`,
      type: "borrow",
      amount: entry.amount,
      debtId,
      note: entry.description,
      external: true,
    },
    totalAmount: 0,
    date: toJsDate(entry.date),
    note: entry.description,
  });

  await batch.commit();
}

/** Reject a shared expense: flip only my consent (no local reflection). */
export async function rejectSharedEntry(entry: SharedEntry): Promise<void> {
  const by = getCurrentActor();
  await updateDoc(doc(db, "sharedEntries", entry.id), {
    status: "rejected",
    pendingForUids: [],
    updatedBy: by,
    updatedAt: serverTimestamp(),
  });
}

// ---- settlement ------------------------------------------------------------

export interface ProposeSettlementInput {
  me: FirebaseUser;
  counterpartyUid: string;
  counterpartyName: string;
  connectionId: string;
  amount: number;
  description: string;
  date: Date;
  workspaceId: string;
  fyStartMonth: number;
  accountId: string; // the payer's account the money leaves
  contacts: Contact[];
  debts: Debt[];
}

/**
 * Propose a settlement: I (the payer) assert I paid the counterparty `amount`.
 * Records my real outflow now (a `repayment` reducing my "owe" shared debt) and
 * creates a pending settlement entry the counterparty must accept to record the
 * matching inflow on their side.
 */
export async function proposeSettlement(input: ProposeSettlementInput): Promise<void> {
  const by = getCurrentActor();
  const batch = writeBatch(db);
  const entryId = newId("sharedEntries");
  const uids = [input.me.uid, input.counterpartyUid] as [string, string];

  batch.set(doc(db, "sharedEntries", entryId), {
    id: entryId,
    connectionId: input.connectionId,
    kind: "settlement" as SharedEntryKind,
    uids,
    creatorUid: input.me.uid,
    counterpartyUid: input.counterpartyUid,
    names: { [input.me.uid]: actorName(input.me), [input.counterpartyUid]: input.counterpartyName },
    payerUid: input.me.uid,
    description: input.description,
    amount: input.amount,
    date: Timestamp.fromDate(input.date),
    status: "pending",
    pendingForUids: [input.counterpartyUid],
    createdBy: by,
    createdAt: serverTimestamp(),
    updatedBy: by,
    updatedAt: serverTimestamp(),
  });

  const ctx: ReflectionCtx = {
    workspaceId: input.workspaceId,
    fyStartMonth: input.fyStartMonth,
    by,
    contacts: input.contacts,
    debts: input.debts,
    newContacts: [],
    newDebts: [],
  };
  // I pay down what I owe them: a repayment against my "owe" shared debt.
  const contactId = findOrCreateSharedContact(
    batch,
    ctx,
    input.counterpartyUid,
    input.counterpartyName,
  );
  const debtId = findOrCreateSharedDebt(batch, ctx, contactId, "owe");
  addReflectionTxn(batch, ctx, {
    sharedEntryId: entryId,
    contactId,
    accountId: input.accountId,
    line: {
      lineId: `settle_${entryId}`,
      type: "repayment",
      amount: input.amount,
      debtId,
      note: input.description,
    },
    totalAmount: -input.amount, // repayment of an "owe" debt: money out
    date: input.date,
    note: input.description,
  });

  await batch.commit();
}

/**
 * Accept a settlement the counterparty proposed: flip my consent and record the
 * matching inflow (a `repayment` of my "owed" shared debt — they paid me back).
 */
export async function acceptSettlement(input: RespondInput): Promise<void> {
  const by = getCurrentActor();
  const { entry } = input;
  const batch = writeBatch(db);

  batch.update(doc(db, "sharedEntries", entry.id), {
    status: "accepted",
    pendingForUids: [],
    updatedBy: by,
    updatedAt: serverTimestamp(),
  });

  const ctx: ReflectionCtx = {
    workspaceId: input.workspaceId,
    fyStartMonth: input.fyStartMonth,
    by,
    contacts: input.contacts,
    debts: input.debts,
    newContacts: [],
    newDebts: [],
  };
  const payerName = entry.names[entry.payerUid] ?? "Partner";
  const contactId = findOrCreateSharedContact(batch, ctx, entry.payerUid, payerName);
  const debtId = findOrCreateSharedDebt(batch, ctx, contactId, "owed");
  // The receiver records the inflow against a real account chosen in the UI;
  // if none is given the inflow is balance-only (external).
  const real = !!input.accountId;
  addReflectionTxn(batch, ctx, {
    sharedEntryId: entry.id,
    contactId,
    accountId: input.accountId ?? EXTERNAL_ACCOUNT,
    line: {
      lineId: `settle_${entry.id}`,
      type: "repayment",
      amount: entry.amount,
      debtId,
      note: entry.description,
      ...(real ? {} : { external: true }),
    },
    totalAmount: real ? entry.amount : 0,
    date: toJsDate(entry.date),
    note: entry.description,
  });

  await batch.commit();
}

// ---- conflict resolution (creator side) ------------------------------------

/**
 * Resolve a rejected shared expense on the creator's side. The creator's
 * reflection (a `lend` to the counterparty) is found by `sharedEntryId`:
 *   - "absorb": rewrite that transaction so the amount becomes the creator's
 *     own expense instead of a receivable, and clear the conflict.
 *   - "remove": delete the reflection transaction (the creator no longer claims
 *     the amount) and clear the conflict.
 * The shared entry is marked resolved either way so the banner clears.
 */
export interface ResolveConflictInput {
  entry: SharedEntry;
  mode: "absorb" | "remove";
  reflectionTxnId: string; // the lend txn whose sharedEntryId == entry.id
  myCategoryId?: string; // category to book the absorbed expense under
  fyStartMonth: number;
  date: Date;
  accountId: string; // the account the original lend came from
  workspaceId: string;
}

export async function resolveConflict(input: ResolveConflictInput): Promise<void> {
  const by = getCurrentActor();
  const batch = writeBatch(db);

  if (input.mode === "absorb") {
    // Rewrite the reflection transaction: lend -> expense (my own cost).
    batch.set(doc(db, "transactions", input.reflectionTxnId), {
      id: input.reflectionTxnId,
      workspaceId: input.workspaceId,
      date: Timestamp.fromDate(input.date),
      accountId: input.accountId,
      sharedEntryId: input.entry.id,
      totalAmount: -input.entry.amount,
      hasSplit: false,
      financialYear: financialYearOf(input.date, input.fyStartMonth),
      note: `${input.entry.description} (absorbed)`,
      createdBy: by,
      createdAt: serverTimestamp(),
      updatedBy: by,
      updatedAt: serverTimestamp(),
      lines: [
        stripUndefined({
          lineId: `absorb_${input.entry.id}`,
          type: "expense",
          amount: input.entry.amount,
          categoryId: input.myCategoryId,
          note: "Absorbed shared share",
        }),
      ],
    });
    appendRevision(batch, {
      workspaceId: input.workspaceId,
      entityType: "transactions",
      entityId: input.reflectionTxnId,
      action: "update",
      by,
    });
  } else {
    batch.delete(doc(db, "transactions", input.reflectionTxnId));
    appendRevision(batch, {
      workspaceId: input.workspaceId,
      entityType: "transactions",
      entityId: input.reflectionTxnId,
      action: "delete",
      by,
    });
  }

  batch.update(doc(db, "sharedEntries", input.entry.id), {
    resolved: true,
    updatedBy: by,
    updatedAt: serverTimestamp(),
  });

  await batch.commit();
}

/** Withdraw a shared entry the creator authored (also drops the reflection). */
export async function withdrawSharedEntry(
  entry: SharedEntry,
  reflectionTxnId: string | null,
): Promise<void> {
  const batch = writeBatch(db);
  batch.delete(doc(db, "sharedEntries", entry.id));
  if (reflectionTxnId) {
    const by = getCurrentActor();
    batch.delete(doc(db, "transactions", reflectionTxnId));
    appendRevision(batch, {
      workspaceId: entry.uids[0], // best-effort; reflection's own ws governs
      entityType: "transactions",
      entityId: reflectionTxnId,
      action: "delete",
      by,
    });
  }
  await batch.commit();
}

function toJsDate(ts: { toDate?: () => Date } | Date): Date {
  if (ts instanceof Date) return ts;
  return ts.toDate ? ts.toDate() : new Date();
}
