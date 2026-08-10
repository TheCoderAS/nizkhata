# Native port status (gap analysis)

Strategy: port all features first; verify/fix the APK build at the very end.

## ✅ Done (in main branch, compiled green at least once)
- Google sign-in (native) + first-login onboarding/seed (roles, categories, workspace)
- Workspace context + RBAC `can()` + workspace switching
- Live Firestore streams for all collections + derivations (balances, net worth,
  debt outstanding, dues, custodial, contact position, spend, trend, budgets, FY)
- Dashboard (net-worth hero, income/expense/net, balances, spend, recent txns)
- Transactions: list + **add form** (expense/income/transfer/borrow/lend/repayment)
- Contacts: list + **create/edit/delete**
- Accounts: screen + **create/edit/delete** (type-conditional metadata)
- Dues / Debts: list views + summaries
- Write layer `mutations.dart` (audited create/update/delete + revisions,
  createTransaction / settleDue / createDebtWithOpening)

## ✅ Done — wave 1 (integrated + routed; build pending)
- Dues: create/edit form + record-payment + cancel/delete
- Debts: create/edit form + record repayment/receipt + delete
- Categories: screen + create/edit/delete (system read-only)
- Budgets: screen (progress) + create/edit/delete
- Contact detail (header stats + Transactions/Debts/Report tabs)
- Activity feed (revisions stream)
- mutations: updateTransaction added; models: line tax parsed

## ✅ Done — wave 2 (integrated + routed; build pending)
- Reports: Insights / FY tax / By category / By contact + CSV (share_plus)  [/reports]
- Account ledger (passbook: running balance + CSV)  [/accounts/:id/ledger]
- Transactions: detail sheet + edit + delete + filters

## ✅ Done — admin write layer
- mutations.dart: createRole/updateRole/duplicateRole/deleteRole, createInvite/
  revokeInvite, changeMemberRole/removeMember/leaveWorkspace, updateWorkspace/
  deleteWorkspace, updateTransaction + GuardrailException (ports adminMutations.ts)

## ✅ Done — wave 3 (integrated + routed; build pending)
- Members: list + invite + role change + remove  [/members]
- Roles: list + create/edit/duplicate/delete + permission grid  [/roles]
- Workspace settings: name/currency/FY-start + delete  [/workspace-settings]
- Profile: sign out, workspaces, leave  [/profile]

## ✅ Done — final wave (integrated + routed; build pending)
- Shared ledger (cross-user): shared_mutations.dart (full sharedMutations.ts
  port + reflection engine), shared_controller.dart (streams), shared_screen.dart
  (summary/inbox/conflicts/partners/history + invite/expense/settle/resolve)  [/shared]
- Transactions: multi-line split entry (quick/split add menu)
- Theme toggle (ThemeController -> MaterialApp; Appearance control in Profile)

## 🎉 FEATURE PORT COMPLETE — all screens/flows ported.
Next: the final build-verification/convergence pass — compile via CI, fix all
accumulated Dart/Gradle errors until the APK builds green + android-latest
publishes.

## N/A on mobile (web-only UX)
- Resizable/column-pref tables (mobile uses lists), marketing Landing page
