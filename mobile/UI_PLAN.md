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

## Phase 2 — roll DataTableView into list screens
Transactions, Dues, Debts, Contacts, Accounts, Categories — each gets a table
presentation matching the web columns, keeping FABs/filters/detail-tap.

## Phase 3 — design system polish (the #5 goal)
- theme.dart: type scale, spacing tokens, tonal surfaces, elevation, button/input/chip
- widgets/common.dart: refined Card, StatCard, SectionCard, EmptyView (with icon),
  add ShimmerSkeleton loading, refined bottom nav (sliding indicator), app bars
- apply consistent padding/rhythm + loading skeletons across all screens

## Phase 4 — final sweep
flutter analyze 0 errors; re-check reachability; update PARITY docs; ensure PR #48
green; report.
