# Deep parity audit — native Flutter vs web (RESOLVED)

5 auditors did a line-by-line web↔native comparison. `flutter analyze` = 0 errors
throughout. Below: what was found and what was fixed.

## ✅ Correctness — verified AT PARITY (money engine)
Transaction sign rules, computeTotal/accountDeltas, debtOutstanding, custodialHeld,
contactPosition, dueSettled/status, netWorthSeries, trendSeries, FY logic,
settleDue/repayment signs, createDebtWithOpening, admin guardrails, Firestore doc
shapes, and the ENTIRE shared-ledger reflection/consent logic — all match the web
exactly. Rules self-audit passed (writes satisfy firestore.rules).

## ✅ FIXED — bugs
- Category spend + budget usage under-counted (only `expense`; now includes
  `interest_expense|fee|tax`). Budgets sort by ratio; over-flag epsilon; fallback name.
- Shared ledger was non-functional for invitees → ported `claimShareInvites`
  (connection now forms on sign-in). `/shared` gated by `shared.view` + tile hidden.
- Contact multi-email interop: now writes `emails[]` + address field.
- Net-worth % badge; custodial card always shown; credit-card "owed" balances
  (list + ledger); account ledger reachable by view-only users.

## ✅ FIXED — missing UI surfaces
- Dues: status + direction filters; row detail sheet (+linked txns); View
  contact/transactions actions. Debts: detail sheet + View actions.
- Dashboard: Upcoming-dues card, Budgets card, trend sparklines on income/expense/net.
- Transactions: category filter, split-only toggle, search box, all 11 line types.
- Account ledger: From/To date filter; Type column (+ in CSV).
- Categories: period selector + per-category Net column.
- Contacts: search box; Family badge; detail header (badges + phone·email·address);
  Debts tab grouped by purpose with direction/status badges.
- Accounts: View-ledger ungated; (account detail dialog still TODO — see below).
- Reports: income/expense trend chart, Top movers, prior-FY %-deltas, by-contact
  donut, tax friendly labels + sort + Lines count.
- Activity: day grouping, entity display names, changed-fields, per-entity icons.

## ⏳ DEFERRED (known, larger — not yet done)
- Tax line ENTRY in the txn forms ({taxable,head,tdsAmount,taxInclusive}) + TDS
  validation. (Engine + tax report already handle tax; forms can't author it yet.)
- Editing MULTI-LINE (split) transactions (single-line edit works).
- Custom date-range period on Dashboard; stacked category-trend chart.
- Account detail dialog (metadata) on row tap; row drill-downs to filtered txns;
  chat-style contact view; sortable table headers; snapshot-retry on shared streams;
  member "active" badge; a few cosmetic label diffs.
