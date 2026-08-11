# Deep parity audit — native Flutter vs web

Baseline: `flutter analyze` = 0 errors. Rules self-audit passed (transactions/
revisions/admin writes satisfy firestore.rules; sharedEntries updates use only
rule-allowed keys). Money-engine correctness verified across 5 auditors.

## ✅ FIXED (correctness / data)
- Category spend + budget spend now count `interest_expense|fee|tax` as expense
  (was `expense`-only → under-reported). derive.dart `_isExpenseSpendLine`.
- budgetProgress sorts by ratio desc; `over` uses +0.005 epsilon; fallback name
  'Uncategorized'.

## Correctness — verified AT PARITY (no fix needed)
Transaction engine sign tables, primaryAccountEffect, computeTotal, accountDeltas,
debtOutstanding, custodialHeld, contactPosition, dueSettled/status, netWorthSeries,
trendSeries, FY logic, settleDue/repayment signs, createDebtWithOpening, admin
guardrails (owner/role-in-use/system-role), Firestore doc shapes for all writes,
report income/expense/savings/by-contact math. (assertNotLastHolder is dead code
in web too — not a gap.)

## HIGH — interop / visibly-wrong (fix next)
- Contact multi-email: native writes only `email`, ignores `emails[]` → editing a
  web contact leaves a STALE emails[] the web keeps showing. Also no address field.
- Reports Tax tab: sort heads by taxable desc; show friendly `taxHeadLabel` + a
  Lines(count) column; CSV include line count.
- Net-worth hero: add the % badge (pct = round(delta/|first|*100)).
- Accounts: credit-card negative balance shown as "X owed" (list/detail/ledger).
- Custodial card on Dashboard: always render (web does).

## MEDIUM — missing UI surfaces
- Dashboard: Upcoming-dues card, Budgets card, trend sparklines on the 3 cards.
- Dues: status + direction filter (settled/cancelled unreachable); row detail view;
  "View contact"/"View transactions" actions. Debts: same detail + view actions.
- Transactions: category filter, split-only toggle, search box; type filter missing
  fee/interest_income/interest_expense/tax (only 7 of 11).
- Account ledger: From/To date filter; a Type column (+ in CSV, for column-compat).
- Categories: period selector + per-category Net column.
- Contacts: search box; Family badge in list; detail header (type/Family/info line);
  Debts tab grouped by purpose with direction/status badges.
- Accounts: "View ledger" should be ungated (view-only users); account detail dialog.
- Reports: income-vs-expense trend chart, category-trend chart, Top movers, prior-FY
  %-delta on stat cards, "Paid by contact" donut.
- Activity: day grouping, entity display name + changed-fields, per-entity icon,
  pagination (native flat list, limit 100).

## LOWER / larger follow-ups
- Tax line entry in the txn forms ({taxable,head,tdsAmount,taxInclusive}) + TDS
  validation → enables FY tax summary data natively.
- Multi-line (split) transaction EDIT (native edits single-line only).
- Custom date-range period (Dashboard).
- Row drill-downs (spend/category/contact → filtered transactions).
- Chat-style contact transaction view; sortable table headers; quick-entry templates;
  card-expiry auto-format; member "active" status badge; Profile title "Profile".

## Auditor 5 — Shared ledger: PENDING
