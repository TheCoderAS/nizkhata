// Firestore data model (§2). Every workspace-scoped doc carries `workspaceId`,
// and every client query MUST filter by it.

import type { Timestamp } from "firebase/firestore";
import type { PermissionMap } from "./permissions";

export type Id = string;

// `Timestamp` in Firestore; we allow Date on the way in for convenience.
export type Ts = Timestamp;

// ---- users -----------------------------------------------------------------
export interface User {
  uid: Id;
  email: string; // lowercased
  displayName: string | null;
  photoURL: string | null;
  createdAt: Ts;
  lastWorkspaceId: Id | null;
}

// ---- workspaces ------------------------------------------------------------
export interface Workspace {
  id: Id;
  name: string;
  ownerId: Id;
  baseCurrency: string; // e.g. "INR"
  fyStartMonth: number; // 1-12; 4 = April (India)
  createdAt: Ts;
}

// ---- memberships -----------------------------------------------------------
// doc id = `${workspaceId}_${uid}`
export interface Membership {
  id: Id;
  workspaceId: Id;
  uid: Id;
  roleId: Id;
  status: "active";
  joinedAt: Ts;
  // Denormalized identity so members can be listed by name/email without
  // reading other users' profiles (Security Rules only allow reading your own).
  email?: string; // lowercased
  displayName?: string | null;
}

// ---- roles -----------------------------------------------------------------
export interface Role {
  id: Id;
  workspaceId: Id;
  name: string;
  isSystem: boolean;
  permissions: PermissionMap;
  createdAt: Ts;
}

// ---- invites ---------------------------------------------------------------
// doc id = `${workspaceId}_${lowercased-email}` (deterministic — see rules FIX 1)
export type InviteStatus = "pending" | "accepted" | "revoked";
export interface Invite {
  id: Id;
  workspaceId: Id;
  email: string; // lowercased
  roleId: Id;
  status: InviteStatus;
  invitedBy: Id;
  createdAt: Ts;
  expiresAt: Ts;
}

// ---- accounts --------------------------------------------------------------
export type AccountType = "cash" | "bank" | "credit_card";
export interface Account {
  id: Id;
  workspaceId: Id;
  name: string;
  type: AccountType;
  openingBalance: number;
  createdAt: Ts;
  createdBy?: Actor;
  updatedBy?: Actor;
  updatedAt?: Ts;
}

// ---- categories ------------------------------------------------------------
export type CategoryKind = "income" | "expense";
export interface Category {
  id: Id;
  workspaceId: Id;
  name: string;
  kind: CategoryKind;
  isSystem: boolean;
  createdAt: Ts;
  createdBy?: Actor;
  updatedBy?: Actor;
  updatedAt?: Ts;
}

// ---- contacts --------------------------------------------------------------
export type ContactType = "person" | "business";
export interface Contact {
  id: Id;
  workspaceId: Id;
  name: string;
  type: ContactType;
  phone?: string;
  email?: string;
  notes?: string;
  createdAt: Ts;
  createdBy?: Actor;
  updatedBy?: Actor;
  updatedAt?: Ts;
}

// ---- debts -----------------------------------------------------------------
// outstanding is DERIVED from linked transaction lines (never stored).
export type DebtDirection = "owe" | "owed"; // owe = you owe them; owed = they owe you
export type DebtPurpose =
  | "loan"
  | "custodial_savings"
  | "lending"
  | "reimbursable"
  | "informal";
export type DebtStatus = "open" | "settled";
export interface Debt {
  id: Id;
  workspaceId: Id;
  contactId: Id;
  direction: DebtDirection;
  purpose: DebtPurpose;
  label?: string;
  note?: string;
  principal: number;
  status: DebtStatus;
  createdAt: Ts;
  createdBy?: Actor;
  updatedBy?: Actor;
  updatedAt?: Ts;
}

// ---- transactions (header + lines) -----------------------------------------
export type LineType =
  | "income"
  | "expense"
  | "transfer_out"
  | "transfer_in"
  | "borrow"
  | "lend"
  | "repayment"
  | "fee"
  | "interest_income"
  | "interest_expense"
  | "tax";

export type TaxHead =
  | "salary"
  | "interest"
  | "capital_gains"
  | "other"
  | "exempt";

export interface LineTax {
  taxable: boolean;
  head: TaxHead;
  tdsAmount: number; // default 0
  taxInclusive: boolean; // is `amount` inclusive of tax?
}

export interface TransactionLine {
  lineId: Id;
  type: LineType;
  amount: number; // always positive; sign implied by type
  categoryId?: Id; // income/expense/interest/fee/tax
  debtId?: Id; // borrow/lend/repayment
  toAccountId?: Id; // transfer_in destination
  tax?: LineTax;
  note?: string;
  // External lines record a debt movement (borrow/lend/repayment) but do NOT
  // move any account balance — e.g. an opening balance against "External / none".
  external?: boolean;
}

export interface Transaction {
  id: Id;
  workspaceId: Id;
  date: Ts;
  note?: string;
  accountId: Id; // primary account money moves through
  contactId?: Id; // required if any line links a debt
  totalAmount: number; // = signed sum of lines; validated on write
  hasSplit: boolean; // lines.length > 1
  dueId?: Id; // set if this txn settles a due
  financialYear: string; // e.g. "2025-26"
  createdBy: Actor;
  createdAt: Ts;
  updatedBy?: Actor;
  updatedAt?: Ts;
  lines: TransactionLine[];
}

// ---- audit / revisions -----------------------------------------------------
// Multi-user workspaces track who created/updated each entity and keep a
// revision log. Actor identity is denormalized (uid + name) so it can be shown
// without reading other users' profiles (Security Rules forbid that).

export interface Actor {
  uid: Id;
  name: string; // displayName || email || short uid, captured at write time
}

/** Audit fields mixed into mutable workspace entities. */
export interface AuditFields {
  createdBy?: Actor;
  createdAt: Ts;
  updatedBy?: Actor;
  updatedAt?: Ts;
}

export type RevisionAction = "create" | "update" | "delete";

// revisions/{revisionId}. Append-only history; written by the client today,
// designed so a Firestore-trigger Cloud Function can take over later with no
// migration. `entityType` is the collection name (e.g. "transactions").
export interface Revision {
  id: Id;
  workspaceId: Id;
  entityType: string;
  entityId: Id;
  action: RevisionAction;
  at: Ts;
  by: Actor;
  // shallow snapshot of the doc after the change (omitted for deletes)
  snapshot?: Record<string, unknown>;
  // changed field names for updates (best-effort, client-computed)
  changedFields?: string[];
}

// ---- dues ------------------------------------------------------------------
// amountSettled is DERIVED from txns where txn.dueId == this.id.
export type DueDirection = "payable" | "receivable";
export type DueStatus = "open" | "partial" | "settled" | "cancelled";
export interface Due {
  id: Id;
  workspaceId: Id;
  direction: DueDirection;
  title: string;
  contactId?: Id;
  accountId?: Id;
  amount: number;
  dueDate: Ts;
  status: DueStatus;
  createdAt: Ts;
  createdBy?: Actor;
  updatedBy?: Actor;
  updatedAt?: Ts;
}
