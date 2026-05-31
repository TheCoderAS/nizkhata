// Human-readable labels for transaction line types. Shared by the transaction
// form (the Type picker) and the detail dialog (the line badge) so the casing
// stays consistent everywhere.

import type { LineType } from "@/types/models";

export const LINE_TYPE_LABELS: Record<LineType, string> = {
  income: "Income",
  expense: "Expense",
  transfer_out: "Transfer out",
  transfer_in: "Transfer in",
  borrow: "Borrow",
  lend: "Lend",
  repayment: "Repayment",
  fee: "Fee",
  interest_income: "Interest income",
  interest_expense: "Interest expense",
  tax: "Tax / GST",
};

/** Label for a line type, falling back to the raw key if unknown. */
export function lineTypeLabel(type: LineType): string {
  return LINE_TYPE_LABELS[type] ?? type;
}
