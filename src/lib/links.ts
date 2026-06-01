// Builders for cross-screen deep-links. Keeping these in one place keeps the
// URL shape consistent and makes the Transactions filter params the single
// source of truth (see the deep-link effect in pages/Transactions.tsx).

export type TxnFilterParam = "account" | "contact" | "category" | "type";

/** A link to the Transactions list pre-filtered by one dimension. */
export function txnsByParam(param: TxnFilterParam, id: string): string {
  return `/transactions?${param}=${encodeURIComponent(id)}`;
}

export const txnsByCategory = (id: string) => txnsByParam("category", id);
export const txnsByAccount = (id: string) => txnsByParam("account", id);
export const txnsByContact = (id: string) => txnsByParam("contact", id);

/** A link to a contact's detail page. */
export const contactDetailPath = (id: string) => `/contacts/${id}`;

/** A link to an account's ledger (passbook) page. */
export const accountLedgerPath = (id: string) => `/settings/accounts/${id}/ledger`;
