// Transaction engine (§2, §6.3). The single source of truth for:
//   - how each line type affects an account balance (sign),
//   - the signed total of a transaction,
//   - line-level + transaction-level validation.
//
// Balances, debt outstanding, contact positions and tax totals are all DERIVED
// from these primitives — nothing is persisted (§1 "derived-not-stored").

import type {
  Account,
  Debt,
  LineType,
  Transaction,
  TransactionLine,
} from "@/types/models";

// Sign each line type applies to the *primary* account (accountId).
// `transfer_in` is special: it credits `toAccountId`, not the primary account.
// `repayment` is direction-dependent and resolved separately.
const PRIMARY_SIGN: Record<LineType, 1 | -1 | 0> = {
  income: +1,
  interest_income: +1,
  borrow: +1,
  expense: -1,
  interest_expense: -1,
  fee: -1,
  tax: -1, // default −; sign-by-context handled by caller if needed
  lend: -1,
  transfer_out: -1,
  transfer_in: 0, // affects toAccountId instead
  repayment: 0, // resolved via linked debt direction
};

const MONEY_EPSILON = 0.005; // half a paisa/cent tolerance for float sums

export function roundMoney(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

/**
 * Signed effect of a single line on the *primary* account (accountId).
 * For `repayment` you must pass the linked debt so direction can be resolved:
 *   - direction "owe"  (you owe them)  -> paying it down leaves your account: −
 *   - direction "owed" (they owe you)  -> they pay you back, money in:        +
 * `transfer_in` returns 0 here because it credits toAccountId (see below).
 */
export function primaryAccountEffect(
  line: TransactionLine,
  debt?: Debt,
): number {
  if (line.type === "repayment") {
    if (!debt) return 0;
    return (debt.direction === "owe" ? -1 : +1) * line.amount;
  }
  return PRIMARY_SIGN[line.type] * line.amount;
}

/** Signed total of a transaction on its primary account (= header.totalAmount). */
export function computeTotal(
  lines: TransactionLine[],
  debtsById: Record<string, Debt> = {},
): number {
  let total = 0;
  for (const line of lines) {
    total += primaryAccountEffect(
      line,
      line.debtId ? debtsById[line.debtId] : undefined,
    );
  }
  return roundMoney(total);
}

/**
 * Net delta applied to every account touched by a transaction, keyed by
 * accountId. Primary account gets the sum of primary effects; each
 * `transfer_in` line credits its `toAccountId`. This is the function account
 * balances are derived from.
 */
export function accountDeltas(
  txn: Pick<Transaction, "accountId" | "lines">,
  debtsById: Record<string, Debt> = {},
): Record<string, number> {
  const deltas: Record<string, number> = {};
  const add = (acct: string, amt: number) => {
    deltas[acct] = roundMoney((deltas[acct] ?? 0) + amt);
  };

  for (const line of txn.lines) {
    if (line.type === "transfer_in") {
      if (line.toAccountId) add(line.toAccountId, +line.amount);
      continue;
    }
    add(
      txn.accountId,
      primaryAccountEffect(line, line.debtId ? debtsById[line.debtId] : undefined),
    );
  }
  return deltas;
}

/** Current balance of an account = openingBalance + sum of all deltas. */
export function accountBalance(
  account: Account,
  txns: Transaction[],
  debtsById: Record<string, Debt> = {},
): number {
  let bal = account.openingBalance;
  for (const txn of txns) {
    const deltas = accountDeltas(txn, debtsById);
    bal += deltas[account.id] ?? 0;
  }
  return roundMoney(bal);
}

// ---- validation ------------------------------------------------------------

export interface ValidationIssue {
  lineId?: string;
  field?: string;
  message: string;
}

const LINE_TYPES_NEEDING_DEBT: LineType[] = ["borrow", "lend", "repayment"];

/**
 * Validates a single line in isolation (shape rules). Cross-line and
 * header rules live in `validateTransaction`.
 */
export function validateLine(line: TransactionLine): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const at = (field: string, message: string) =>
    issues.push({ lineId: line.lineId, field, message });

  if (!(line.amount > 0)) at("amount", "Amount must be greater than 0.");

  if (LINE_TYPES_NEEDING_DEBT.includes(line.type) && !line.debtId) {
    at("debtId", `A ${line.type} line must link a debt.`);
  }

  if (line.type === "transfer_in" && !line.toAccountId) {
    at("toAccountId", "A transfer-in line must have a destination account.");
  }

  if (line.tax) {
    if (line.tax.tdsAmount < 0) at("tax", "TDS amount cannot be negative.");
    if (line.tax.tdsAmount > line.amount)
      at("tax", "TDS amount cannot exceed the line amount.");
  }

  return issues;
}

export interface TransactionDraft {
  accountId?: string;
  contactId?: string;
  lines: TransactionLine[];
  totalAmount?: number; // if provided, must reconcile to computed total
}

/**
 * Full transaction validation (§6.3 live validation):
 *   - at least one line
 *   - each line valid in isolation
 *   - borrow/lend/repayment require a contact on the header
 *   - every transfer_out is paired with a transfer_in (and amounts balance)
 *   - transfer_in destination differs from the source account
 *   - if totalAmount supplied, it reconciles to the computed signed total
 */
export function validateTransaction(
  draft: TransactionDraft,
  debtsById: Record<string, Debt> = {},
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const { lines } = draft;

  if (!draft.accountId) issues.push({ field: "accountId", message: "Pick an account." });

  if (lines.length === 0) {
    issues.push({ message: "A transaction needs at least one line." });
    return issues;
  }

  for (const line of lines) issues.push(...validateLine(line));

  const linksDebt = lines.some((l) => LINE_TYPES_NEEDING_DEBT.includes(l.type));
  if (linksDebt && !draft.contactId) {
    issues.push({
      field: "contactId",
      message: "Borrow / lend / repayment lines require a contact on the transaction.",
    });
  }

  // transfer pairing: sum(transfer_out) must equal sum(transfer_in)
  const outSum = lines
    .filter((l) => l.type === "transfer_out")
    .reduce((s, l) => s + l.amount, 0);
  const inSum = lines
    .filter((l) => l.type === "transfer_in")
    .reduce((s, l) => s + l.amount, 0);
  if (Math.abs(outSum - inSum) > MONEY_EPSILON) {
    issues.push({
      message: "Transfer lines must balance: total transfer-out must equal total transfer-in.",
    });
  }
  for (const l of lines) {
    if (l.type === "transfer_in" && l.toAccountId && l.toAccountId === draft.accountId) {
      issues.push({
        lineId: l.lineId,
        field: "toAccountId",
        message: "Transfer destination must differ from the source account.",
      });
    }
  }

  if (draft.totalAmount !== undefined) {
    const computed = computeTotal(lines, debtsById);
    if (Math.abs(computed - draft.totalAmount) > MONEY_EPSILON) {
      issues.push({
        field: "totalAmount",
        message: `Lines do not reconcile: header total ${draft.totalAmount} vs computed ${computed}.`,
      });
    }
  }

  return issues;
}

export function isValidTransaction(
  draft: TransactionDraft,
  debtsById: Record<string, Debt> = {},
): boolean {
  return validateTransaction(draft, debtsById).length === 0;
}
