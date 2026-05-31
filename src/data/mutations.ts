// Thin write helpers for workspace-scoped collections. Each injects workspaceId
// and a doc id, and uses serverTimestamp() for createdAt where relevant. Security
// Rules independently enforce permissions; these are just convenience wrappers.

import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  serverTimestamp,
  updateDoc,
  writeBatch,
} from "firebase/firestore";
import { db } from "@/firebase/config";
import { financialYearOf } from "@/lib/financialYear";
import { getCurrentActor, getCurrentWorkspaceId } from "./actor";
import { appendRevision } from "./revisions";
import type {
  Account,
  Actor,
  Budget,
  Category,
  Contact,
  Debt,
  Due,
  Transaction,
  TransactionLine,
} from "@/types/models";

// Sentinel accountId for transactions whose lines don't move any real account
// (e.g. an opening balance booked against "External / none").
export const EXTERNAL_ACCOUNT = "__external__";

export function newId(name: string): string {
  return doc(collection(db, name)).id;
}

// ---- audited write helpers -------------------------------------------------
// Every entity create/update/delete also stamps audit fields (createdBy/
// updatedBy as denormalized Actors) and appends an append-only revision in the
// same batch. The current actor comes from the module-level holder (set by
// AuthProvider), so call sites don't need to thread it through.

/** Create a workspace-scoped doc with audit fields + a "create" revision. */
async function auditedCreate(
  collectionName: string,
  workspaceId: string,
  data: Record<string, unknown>,
  id = newId(collectionName),
): Promise<string> {
  const by = getCurrentActor();
  const docData = {
    id,
    workspaceId,
    ...stripUndefined(data),
    createdBy: by,
    createdAt: serverTimestamp(),
    updatedBy: by,
    updatedAt: serverTimestamp(),
  };
  const batch = writeBatch(db);
  batch.set(doc(db, collectionName, id), docData);
  appendRevision(batch, {
    workspaceId,
    entityType: collectionName,
    entityId: id,
    action: "create",
    by,
    snapshot: stripUndefined(data),
  });
  await batch.commit();
  return id;
}

/** Update a doc: refresh updatedBy/updatedAt + append an "update" revision. */
async function auditedUpdate(
  collectionName: string,
  id: string,
  data: Record<string, unknown>,
): Promise<void> {
  const by = getCurrentActor();
  const workspaceId = getCurrentWorkspaceId();
  const clean = stripUndefined(data);
  const batch = writeBatch(db);
  batch.update(doc(db, collectionName, id), {
    ...clean,
    updatedBy: by,
    updatedAt: serverTimestamp(),
  });
  appendRevision(batch, {
    workspaceId,
    entityType: collectionName,
    entityId: id,
    action: "update",
    by,
    snapshot: clean,
    changedFields: Object.keys(clean),
  });
  await batch.commit();
}

/** Delete a doc + append a "delete" revision. */
async function auditedDelete(
  collectionName: string,
  id: string,
): Promise<void> {
  const by = getCurrentActor();
  const workspaceId = getCurrentWorkspaceId();
  const batch = writeBatch(db);
  batch.delete(doc(db, collectionName, id));
  appendRevision(batch, {
    workspaceId,
    entityType: collectionName,
    entityId: id,
    action: "delete",
    by,
  });
  await batch.commit();
}

// ---- accounts --------------------------------------------------------------
export async function createAccount(
  workspaceId: string,
  data: Pick<Account, "name" | "type" | "openingBalance">,
): Promise<string> {
  return auditedCreate("accounts", workspaceId, data);
}
export async function updateAccount(
  id: string,
  data: Partial<Pick<Account, "name" | "type" | "openingBalance">>,
) {
  await auditedUpdate("accounts", id, data);
}
export async function deleteAccount(id: string) {
  await auditedDelete("accounts", id);
}

// ---- categories ------------------------------------------------------------
export async function createCategory(
  workspaceId: string,
  data: Pick<Category, "name" | "kind">,
): Promise<string> {
  return auditedCreate("categories", workspaceId, { ...data, isSystem: false });
}
export async function updateCategory(
  id: string,
  data: Partial<Pick<Category, "name" | "kind">>,
) {
  await auditedUpdate("categories", id, data);
}
export async function deleteCategory(id: string) {
  await auditedDelete("categories", id);
}

// ---- contacts --------------------------------------------------------------
export async function createContact(
  workspaceId: string,
  data: Pick<Contact, "name" | "type"> & Partial<Pick<Contact, "phone" | "email" | "notes">>,
): Promise<string> {
  return auditedCreate("contacts", workspaceId, data);
}
export async function updateContact(
  id: string,
  data: Partial<Pick<Contact, "name" | "type" | "phone" | "email" | "notes">>,
) {
  await auditedUpdate("contacts", id, data);
}
export async function deleteContact(id: string) {
  await auditedDelete("contacts", id);
}

// ---- budgets ---------------------------------------------------------------
export async function createBudget(
  workspaceId: string,
  data: Pick<Budget, "categoryId" | "amount" | "period">,
): Promise<string> {
  return auditedCreate("budgets", workspaceId, data);
}
export async function updateBudget(
  id: string,
  data: Partial<Pick<Budget, "amount" | "categoryId" | "period">>,
) {
  await auditedUpdate("budgets", id, data);
}
export async function deleteBudget(id: string) {
  await auditedDelete("budgets", id);
}

// The cross-user shared ledger (Splitwise-style) lives in `sharedMutations.ts`,
// not here: those collections are keyed by user uid, not workspaceId, and so
// don't fit the workspace-scoped audited helpers above. Each side's local
// reflection of an agreed shared item IS a normal workspace debt/transaction
// and is built there by reusing these primitives.

// ---- debts -----------------------------------------------------------------
export async function createDebt(
  workspaceId: string,
  data: Pick<Debt, "contactId" | "direction" | "purpose" | "principal"> &
    Partial<Pick<Debt, "label">>,
): Promise<string> {
  return auditedCreate("debts", workspaceId, { ...data, status: "open" });
}
export async function updateDebt(
  id: string,
  data: Partial<Pick<Debt, "label" | "note" | "principal" | "status">>,
) {
  await auditedUpdate("debts", id, data);
}
export async function deleteDebt(id: string) {
  await auditedDelete("debts", id);
}

/**
 * Create a debt and, when `openingAmount > 0`, an opening-balance transaction
 * dated today with a single line linked to the debt:
 *   - direction "owe"  (you owe them)  -> `borrow`  (+ to your account)
 *   - direction "owed" (they owe you)  -> `lend`    (− from your account)
 * If `accountId` is omitted (External / none), the line is flagged `external`
 * so it records the debt without moving any account balance.
 *
 * Outstanding is always derived from these lines, so editing/deleting the
 * opening transaction later keeps the debt consistent automatically.
 */
export async function createDebtWithOpening(
  workspaceId: string,
  _createdByUid: string, // retained for call-site compat; actor comes from holder
  fyStartMonth: number,
  debtData: Pick<Debt, "contactId" | "direction" | "purpose" | "principal"> &
    Partial<Pick<Debt, "label" | "note">>,
  opening: { amount: number; accountId?: string; date?: Date },
): Promise<string> {
  const by = getCurrentActor();
  const debtId = newId("debts");
  const batch = writeBatch(db);

  const debtDoc = { ...stripUndefined(debtData), status: "open" as const };
  batch.set(doc(db, "debts", debtId), {
    id: debtId,
    workspaceId,
    ...debtDoc,
    createdBy: by,
    createdAt: serverTimestamp(),
    updatedBy: by,
    updatedAt: serverTimestamp(),
  });
  appendRevision(batch, {
    workspaceId,
    entityType: "debts",
    entityId: debtId,
    action: "create",
    by,
    snapshot: debtDoc,
  });

  if (opening.amount > 0) {
    const txnId = newId("transactions");
    const external = !opening.accountId;
    const lineType = debtData.direction === "owe" ? "borrow" : "lend";
    const line: TransactionLine = {
      lineId: `open_${Date.now()}`,
      type: lineType,
      amount: opening.amount,
      debtId,
      note: "Opening balance",
      ...(external ? { external: true } : {}),
    };
    const when = opening.date ?? new Date();
    batch.set(doc(db, "transactions", txnId), {
      id: txnId,
      workspaceId,
      date: Timestamp.fromDate(when),
      accountId: opening.accountId ?? EXTERNAL_ACCOUNT,
      contactId: debtData.contactId,
      // external line contributes 0; a real account records the signed movement
      totalAmount: external
        ? 0
        : (debtData.direction === "owe" ? 1 : -1) * opening.amount,
      hasSplit: false,
      financialYear: financialYearOf(when, fyStartMonth),
      note: "Opening balance",
      createdBy: by,
      createdAt: serverTimestamp(),
      updatedBy: by,
      updatedAt: serverTimestamp(),
      lines: [stripUndefined(line)],
    });
    appendRevision(batch, {
      workspaceId,
      entityType: "transactions",
      entityId: txnId,
      action: "create",
      by,
    });
  }

  await batch.commit();
  return debtId;
}

// ---- dues ------------------------------------------------------------------
export async function createDue(
  workspaceId: string,
  data: Pick<Due, "direction" | "title" | "amount" | "dueDate"> &
    Partial<Pick<Due, "contactId" | "accountId">>,
): Promise<string> {
  return auditedCreate("dues", workspaceId, { ...data, status: "open" });
}
export async function updateDue(
  id: string,
  data: Partial<
    Pick<Due, "direction" | "title" | "amount" | "dueDate" | "status" | "contactId" | "accountId">
  >,
) {
  await auditedUpdate("dues", id, data);
}
export async function deleteDue(id: string) {
  await auditedDelete("dues", id);
}

// ---- transactions ----------------------------------------------------------
export interface TransactionInput {
  date: Date;
  note?: string;
  accountId: string;
  contactId?: string;
  totalAmount: number;
  dueId?: string;
  financialYear: string;
  lines: TransactionLine[];
}

export async function createTransaction(
  workspaceId: string,
  _createdByUid: string, // retained for call-site compat; actor from holder
  input: TransactionInput,
): Promise<string> {
  const by = getCurrentActor();
  const id = newId("transactions");
  const batch = writeBatch(db);
  batch.set(doc(db, "transactions", id), buildTxnDoc(id, workspaceId, by, input));
  appendRevision(batch, {
    workspaceId,
    entityType: "transactions",
    entityId: id,
    action: "create",
    by,
  });
  await batch.commit();
  return id;
}

export async function updateTransaction(
  id: string,
  workspaceId: string,
  createdBy: Actor,
  input: TransactionInput,
) {
  // createdBy must be preserved (rules enforce immutability); pass the original.
  const by = getCurrentActor();
  const batch = writeBatch(db);
  batch.set(doc(db, "transactions", id), buildTxnDoc(id, workspaceId, createdBy, input, by));
  appendRevision(batch, {
    workspaceId,
    entityType: "transactions",
    entityId: id,
    action: "update",
    by,
  });
  await batch.commit();
}

export async function deleteTransaction(id: string) {
  await auditedDelete("transactions", id);
}

function buildTxnDoc(
  id: string,
  workspaceId: string,
  createdBy: Actor,
  input: TransactionInput,
  updatedBy: Actor = createdBy,
): Transaction {
  return {
    id,
    workspaceId,
    date: Timestamp.fromDate(input.date),
    accountId: input.accountId,
    totalAmount: input.totalAmount,
    hasSplit: input.lines.length > 1,
    financialYear: input.financialYear,
    createdBy,
    createdAt: serverTimestamp() as never,
    updatedBy,
    updatedAt: serverTimestamp() as never,
    lines: input.lines.map(stripUndefined),
    ...stripUndefined({
      note: input.note,
      contactId: input.contactId,
      dueId: input.dueId,
    }),
  } as Transaction;
}

/** Settling a due: create the txn and flip the due status in one batch. */
export async function settleDue(
  workspaceId: string,
  _createdByUid: string,
  due: Due,
  input: TransactionInput,
  newStatus: Due["status"],
): Promise<void> {
  const by = getCurrentActor();
  const batch = writeBatch(db);
  const txnId = newId("transactions");
  batch.set(
    doc(db, "transactions", txnId),
    buildTxnDoc(txnId, workspaceId, by, { ...input, dueId: due.id }),
  );
  appendRevision(batch, {
    workspaceId,
    entityType: "transactions",
    entityId: txnId,
    action: "create",
    by,
  });
  batch.update(doc(db, "dues", due.id), {
    status: newStatus,
    updatedBy: by,
    updatedAt: serverTimestamp(),
  });
  appendRevision(batch, {
    workspaceId,
    entityType: "dues",
    entityId: due.id,
    action: "update",
    by,
    changedFields: ["status"],
  });
  await batch.commit();
}

// ---- workspace -------------------------------------------------------------
export async function updateWorkspace(
  id: string,
  data: { name?: string; baseCurrency?: string; fyStartMonth?: number },
) {
  await updateDoc(doc(db, "workspaces", id), stripUndefined(data));
}

export async function deleteWorkspace(id: string) {
  await deleteDoc(doc(db, "workspaces", id));
}

// Firestore rejects `undefined`; drop those keys.
export function stripUndefined<T extends object>(obj: T): T {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj)) if (v !== undefined) out[k] = v;
  return out as T;
}
