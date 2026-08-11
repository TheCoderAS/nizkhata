# Deep parity audit — findings (native Flutter vs web)

Baseline: `flutter analyze` = 0 errors. Rules self-audit: transactions/revisions/
admin writes satisfy firestore.rules; sharedEntries updates use only rule-allowed
keys (status/pendingForUids/resolved). Correctness of the money engine verified by
auditors below.

## Auditor 2 — Dues & Debts ✅ (done)
Correctness: FULL PARITY (settleDue, debt repayment signs, createDebtWithOpening,
doc shapes all match). Gaps:
- [MISSING] Dues: no status filter (stuck on unsettled) + no direction filter →
  settled/cancelled dues unreachable. (Dues.tsx offers Open/Partial/Settled/
  Cancelled/All + Direction.)
- [MISSING] Dues & Debts rows: no "View contact" / "View transactions" actions
  (contacts.view / transactions.view gates unused).
- [MISSING] Dues & Debts: no row-tap detail view (web DueDetail/DebtDetail with
  Remaining/Account/Note/audit + linked transactions).
- [MISMATCH] debt_form: purpose dropdown omits nothing critical ('shared' omitted
  — acceptable/safer). Contact pickers filter connectionUid==null (web lists all).
- [COSMETIC] Dues card labels shorter than web; lineId uses microseconds.

## Auditor 1 — Transactions engine + Dashboard (pending)
## Auditor 3 — Contacts/Accounts/Categories/Budgets (pending)
## Auditor 4 — Reports/Activity/Members/Roles/Workspace/Profile (pending)
## Auditor 5 — Shared ledger (pending)
