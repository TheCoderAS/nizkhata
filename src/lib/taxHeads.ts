// Human-readable labels for tax heads. Shared by the transaction form (the
// Head picker) and any report that groups taxable lines by head, so the casing
// and ordering stay consistent.

import type { TaxHead } from "@/types/models";

export const TAX_HEAD_LABELS: Record<TaxHead, string> = {
  salary: "Salary",
  bonus: "Bonus",
  overtime: "Overtime",
  reimbursement: "Reimbursement",
  perquisite: "Perquisite",
  commission: "Commission",
  professional_fees: "Professional fees",
  rent: "Rent",
  interest: "Interest",
  dividend: "Dividend",
  capital_gains: "Capital gains",
  business: "Business / profession",
  other: "Other",
  exempt: "Exempt",
};

// Display order for the picker.
export const TAX_HEAD_ORDER: TaxHead[] = [
  "salary",
  "bonus",
  "overtime",
  "reimbursement",
  "perquisite",
  "commission",
  "professional_fees",
  "rent",
  "interest",
  "dividend",
  "capital_gains",
  "business",
  "other",
  "exempt",
];

/** Label for a tax head, falling back to the raw key if unknown. */
export function taxHeadLabel(head: string): string {
  return (TAX_HEAD_LABELS as Record<string, string>)[head] ?? head;
}
