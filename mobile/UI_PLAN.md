# v1.0.1 work plan — data tables + UI/UX polish (PR #48)

Verify each phase with `PATH=/root/flutter/bin flutter analyze --no-pub` (0 errors)
before commit+push. Push to branch `claude/android-app` → lands in PR #48.

## Phase 0 — runtime fixes ✅ DONE (bcacbfd, de5f16a)
Contacts route/AppBar; workspaceMembers; sign-out; activity error; admin gating;
budget/due validation; menu de-dup.

## Phase 1 — reusable DataTableView ✅ DONE (column_prefs + data_table_view)
- lib/widgets/data_table_view.dart: horizontally scrollable table with
  - column defs {key, label, cell builder, numeric, width, defaultVisible, locked}
  - SHOW/HIDE columns via a columns menu (persisted per tableKey)
  - RESIZE column widths via draggable header dividers (persisted)
  - tap-header SORT (asc/desc), sticky header row
  - lib/lib/column_prefs.dart: shared_preferences-backed prefs (visible set + widths)

## Phase 2 — roll DataTableView into list screens ✅ DONE (all 6: transactions/dues/debts/contacts/accounts/categories)
Transactions, Dues, Debts, Contacts, Accounts, Categories — each gets a table
presentation matching the web columns, keeping FABs/filters/detail-tap.

## Phase 3 — design system polish (the #5 goal) ✅ DONE
- theme.dart: type scale, spacing tokens, tonal surfaces, elevation, button/input/chip ✅
- widgets/common.dart: refined Card, StatCard, SectionCard, EmptyView (with icon),
  Skeleton + ListSkeleton shimmer loaders, refined bottom nav (indicator + labels) ✅
- dashboard: segmented period control + section "See all" navigation ✅
- contextual EmptyView icons on every screen; shimmer loaders on shared/activity ✅
- column_prefs moved to lib/core (fixed relative-lib import) ✅

## Phase 4 — final sweep ✅ DONE
flutter analyze 0 errors / 0 warnings ✅ (37 info-level deprecations remain, non-blocking).
Deep action-by-action parity audit (web vs Flutter) across ALL domains → gaps fixed:
- Foundation: `/transactions` route accepts initial filters → "View transactions"
  cross-navigation wired from accounts, categories, contacts, budgets, dues, debts,
  dashboard, reports. ✅
- Transactions: split/multi-line txns now editable (HIGH); per-line tax entry;
  linked due/debt chips; external/tax badges; financial-year field. ✅
- Dues/Debts: search boxes; view-transactions action; detail-sheet Edit + Record
  payment / receipt / repayment actions. ✅
- Accounts: read-only detail sheet (metadata + type badge + masked id) for all users;
  cc safety note; MM/YY expiry auto-format; ledger header badge. ✅
- Categories: custom date-range period; view-transactions for viewers. ✅
- Budgets: tappable cards → filtered txns; per-group totals; resolved period labels. ✅
- Contacts: multiple labeled emails + validation; view-transactions; open-in-txns;
  tappable chat-style transaction timeline. ✅
- Dashboard: custom date range; tappable recent txns; spend drill-downs. ✅
- Reports: spend-by-category-over-time stacked chart; row drill-downs. ✅
- Activity: load-more pagination. ✅
- Workspace: create-workspace action (More + Profile). ✅
- Per-entity RevisionHistory (audit footer + timeline) on txn/due/debt/account detail. ✅
