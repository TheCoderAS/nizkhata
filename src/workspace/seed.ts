// Seed data (§7) and helpers to build the documents written on first login.

import type { CategoryKind } from "@/types/models";
import {
  SYSTEM_ROLE_ORDER,
  SYSTEM_ROLE_TEMPLATES,
  type SystemRoleName,
} from "@/types/permissions";

export interface SeedRoleSpec {
  name: SystemRoleName;
  isSystem: true;
  permissions: ReturnType<() => (typeof SYSTEM_ROLE_TEMPLATES)[SystemRoleName]>;
}

export function systemRoleSpecs(): SeedRoleSpec[] {
  return SYSTEM_ROLE_ORDER.map((name) => ({
    name,
    isSystem: true,
    permissions: SYSTEM_ROLE_TEMPLATES[name],
  }));
}

export interface SeedCategorySpec {
  name: string;
  kind: CategoryKind;
}

// Default categories (§7).
export const DEFAULT_CATEGORIES: SeedCategorySpec[] = [
  // Income
  { name: "Salary", kind: "income" },
  { name: "Bonus", kind: "income" },
  { name: "Interest (CASA/FD)", kind: "income" },
  { name: "Gift", kind: "income" },
  { name: "Reimbursement", kind: "income" },
  { name: "Refund", kind: "income" },
  { name: "Other Income", kind: "income" },
  // Expense
  { name: "Food", kind: "expense" },
  { name: "Transport", kind: "expense" },
  { name: "Rent", kind: "expense" },
  { name: "Utilities", kind: "expense" },
  { name: "Shopping", kind: "expense" },
  { name: "Health", kind: "expense" },
  { name: "Entertainment", kind: "expense" },
  { name: "Loan Interest", kind: "expense" },
  { name: "Bank Charges", kind: "expense" },
  { name: "Taxes & GST", kind: "expense" },
  { name: "Other Expense", kind: "expense" },
];
