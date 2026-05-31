// Thin write helpers for workspace-scoped collections. Each injects workspaceId
// and a doc id, and uses serverTimestamp() for createdAt where relevant. Security
// Rules independently enforce permissions; these are just convenience wrappers.

import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from "firebase/firestore";
import { db } from "@/firebase/config";
import { financialYearOf } from "@/lib/financialYear";
import type {
  Account,
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

function newId(name: string): string {
  return doc(collection(db, name)).id;
}

// ---- accounts --------------------------------------------------------------
export async function createAccount(
  workspaceId: string,
  data: Pick<Account, "name" | "type" | "openingBalance">,
): Promise<string> {
  const id = newId("accounts");
  await setDoc(doc(db, "accounts", id), {
    id,
    workspaceId,
    ...data,
    createdAt: serverTimestamp(),
  });
  return id;
}
export async function updateAccount(
  id: string,
  data: Partial<Pick<Account, "name" | "type" | "openingBalance">>,
) {
  await updateDoc(doc(db, "accounts", id), data);
}
export async function deleteAccount(id: string) {
  await deleteDoc(doc(db, "accounts", id));
}

// ---- categories ------------------------------------------------------------
export async function createCategory(
  workspaceId: string,
  data: Pick<Category, "name" | "kind">,
): Promise<string> {
  const id = newId("categories");
  await setDoc(doc(db, "categories", id), {
    id,
    workspaceId,
    ...data,
    isSystem: false,
    createdAt: serverTimestamp(),
  });
  return id;
}
export async function updateCategory(
  id: string,
  data: Partial<Pick<Category, "name" | "kind">>,
) {
  await updateDoc(doc(db, "categories", id), data);
}
export async function deleteCategory(id: string) {
  await deleteDoc(doc(db, "categories", id));
}

// ---- contacts --------------------------------------------------------------
export async function createContact(
  workspaceId: string,
  data: Pick<Contact, "name" | "type"> & Partial<Pick<Contact, "phone" | "email" | "notes">>,
): Promise<string> {
  const id = newId("contacts");
  await setDoc(doc(db, "contacts", id), {
    id,
    workspaceId,
    ...stripUndefined(data),
    createdAt: serverTimestamp(),
  });
  return id;
}
export async function updateContact(
  id: string,
  data: Partial<Pick<Contact, "name" | "type" | "phone" | "email" | "notes">>,
) {
  await updateDoc(doc(db, "contacts", id), stripUndefined(data));
}
export async function deleteContact(id: string) {
  await deleteDoc(doc(db, "contacts", id));
}

// ---- debts -----------------------------------------------------------------
export async function createDebt(
  workspaceId: string,
  data: Pick<Debt, "contactId" | "direction" | "purpose" | "principal"> &
    Partial<Pick<Debt, "label">>,
): Promise<string> {
  const id = newId("debts");
  await setDoc(doc(db, "debts", id), {
    id,
    workspaceId,
    ...stripUndefined(data),
    status: "open",
    createdAt: serverTimestamp(),
  });
  return id;
}
export async function updateDebt(
  id: string,
  data: Partial<Pick<Debt, "label" | "principal" | "status">>,
) {
  await updateDoc(doc(db, "debts", id), stripUndefined(data));
}
export async function deleteDebt(id: string) {
  await deleteDoc(doc(db, "debts", id));
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
  createdBy: string,
  fyStartMonth: number,
  debtData: Pick<Debt, "contactId" | "direction" | "purpose" | "principal"> &
    Partial<Pick<Debt, "label">>,
  opening: { amount: number; accountId?: string },
): Promise<string> {
  const debtId = newId("debts");
  const batch = writeBatch(db);

  batch.set(doc(db, "debts", debtId), {
    id: debtId,
    workspaceId,
    ...stripUndefined(debtData),
    status: "open",
    createdAt: serverTimestamp(),
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
    const now = new Date();
    batch.set(doc(db, "transactions", txnId), {
      id: txnId,
      workspaceId,
      date: Timestamp.fromDate(now),
      accountId: opening.accountId ?? EXTERNAL_ACCOUNT,
      contactId: debtData.contactId,
      // external line contributes 0; a real account records the signed movement
      totalAmount: external
        ? 0
        : (debtData.direction === "owe" ? 1 : -1) * opening.amount,
      hasSplit: false,
      financialYear: financialYearOf(now, fyStartMonth),
      note: "Opening balance",
      createdBy,
      createdAt: serverTimestamp(),
      lines: [stripUndefined(line)],
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
  const id = newId("dues");
  await setDoc(doc(db, "dues", id), {
    id,
    workspaceId,
    ...stripUndefined(data),
    status: "open",
    createdAt: serverTimestamp(),
  });
  return id;
}
export async function updateDue(
  id: string,
  data: Partial<
    Pick<Due, "direction" | "title" | "amount" | "dueDate" | "status" | "contactId" | "accountId">
  >,
) {
  await updateDoc(doc(db, "dues", id), stripUndefined(data));
}
export async function deleteDue(id: string) {
  await deleteDoc(doc(db, "dues", id));
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
  createdBy: string,
  input: TransactionInput,
): Promise<string> {
  const id = newId("transactions");
  await setDoc(doc(db, "transactions", id), buildTxnDoc(id, workspaceId, createdBy, input));
  return id;
}

export async function updateTransaction(
  id: string,
  workspaceId: string,
  createdBy: string,
  input: TransactionInput,
) {
  // createdBy must be preserved (rules enforce this); pass the original.
  const data = buildTxnDoc(id, workspaceId, createdBy, input);
  await setDoc(doc(db, "transactions", id), data);
}

export async function deleteTransaction(id: string) {
  await deleteDoc(doc(db, "transactions", id));
}

function buildTxnDoc(
  id: string,
  workspaceId: string,
  createdBy: string,
  input: TransactionInput,
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
  createdBy: string,
  due: Due,
  input: TransactionInput,
  newStatus: Due["status"],
): Promise<void> {
  const batch = writeBatch(db);
  const txnId = newId("transactions");
  batch.set(
    doc(db, "transactions", txnId),
    buildTxnDoc(txnId, workspaceId, createdBy, { ...input, dueId: due.id }),
  );
  batch.update(doc(db, "dues", due.id), { status: newStatus });
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
function stripUndefined<T extends object>(obj: T): T {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj)) if (v !== undefined) out[k] = v;
  return out as T;
}
