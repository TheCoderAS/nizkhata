import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'screens/account_ledger_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/activity_screen.dart';
import 'screens/budgets_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/choose_currency_screen.dart';
import 'screens/contact_detail_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/debts_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/categorize_screen.dart';
import 'screens/dues_screen.dart';
import 'screens/import_screen.dart';
import 'screens/login_screen.dart';
import 'screens/members_screen.dart';
import 'screens/more_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/roles_screen.dart';
import 'screens/shared_screen.dart';
import 'screens/workspace_settings_screen.dart';
import 'screens/shell.dart';
import 'screens/transactions_screen.dart';
import 'state/auth_controller.dart';

/// Translate an incoming web-app deep-link path (https://nizkhata.web.app/...)
/// to the native route. The web app nests several screens under /settings/*
/// where the app uses top-level routes; returns null when [loc] is already a
/// native path (so redirect doesn't loop).
String? mapDeepLinkPath(String loc) {
  if (loc == '/' || loc.isEmpty) return '/dashboard';
  if (loc == '/settings/account') return '/profile';
  if (loc == '/settings/workspace') return '/workspace-settings';
  final ledger = RegExp(r'^/settings/accounts/([^/]+)/ledger$').firstMatch(loc);
  if (ledger != null) return '/accounts/${ledger.group(1)}/ledger';
  const prefixMap = {
    '/settings/accounts': '/accounts',
    '/settings/categories': '/categories',
    '/settings/budgets': '/budgets',
    '/settings/members': '/members',
    '/settings/roles': '/roles',
  };
  return prefixMap[loc];
}

/// Where [loc] should go instead, given the sign-in state, or null to stay.
/// Pure so the first-run gate can be tested without Firebase.
String? authRedirect(
  String loc, {
  required bool loading,
  required bool signedIn,
  required bool needsWorkspace,
}) {
  // Remap web-app deep-link paths (/settings/*, /) to native routes first.
  final mapped = mapDeepLinkPath(loc);
  if (mapped != null) return mapped;
  final loggingIn = loc == '/login';
  if (loading) return null;
  if (!signedIn) return loggingIn ? null : '/login';
  // A first sign-in has no workspace yet and must choose its currency before
  // one exists. Every other route assumes a workspace, so all of them (deep
  // links and notification taps included) wait behind that screen.
  final choosing = loc == '/welcome';
  if (needsWorkspace) return choosing ? null : '/welcome';
  if (loggingIn || choosing) return '/dashboard';
  return null;
}

GoRouter buildRouter(AuthController auth) {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: auth,
    // Any deep link that matches no route falls back to the dashboard.
    onException: (_, __, router) => router.go('/dashboard'),
    redirect: (context, state) => authRedirect(
      state.matchedLocation,
      loading: auth.loading,
      signedIn: auth.user != null,
      needsWorkspace: auth.needsWorkspace,
    ),
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const ChooseCurrencyScreen()),
      GoRoute(path: '/accounts', builder: (_, __) => const AccountsScreen()),
      GoRoute(path: '/categories', builder: (_, __) => const CategoriesScreen()),
      GoRoute(path: '/budgets', builder: (_, __) => const BudgetsScreen()),
      GoRoute(path: '/activity', builder: (_, __) => const ActivityScreen()),
      GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
      GoRoute(path: '/shared', builder: (_, __) => const SharedScreen()),
      GoRoute(path: '/members', builder: (_, __) => const MembersScreen()),
      GoRoute(path: '/roles', builder: (_, __) => const RolesScreen()),
      GoRoute(path: '/workspace-settings', builder: (_, __) => const WorkspaceSettingsScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
        path: '/accounts/:id/ledger',
        builder: (_, state) => AccountLedgerScreen(accountId: state.pathParameters['id']!),
      ),
      // Standalone filtered transactions view (drill-down target from other
      // screens). Kept OUTSIDE the shell so it renders its own AppBar + back
      // button — pushing a shell-branch route imperatively renders a blank
      // shell child, which is why drill-downs use /txns, not /transactions.
      GoRoute(
        path: '/txns',
        builder: (_, state) {
          final q = state.uri.queryParameters;
          return TransactionsScreen(
            standalone: true,
            initialDate: q['date'] == null ? null : DateTime.tryParse(q['date']!),
            initialAccount: q['account'],
            initialContact: q['contact'],
            initialCategory: q['category'],
            initialType: q['type'],
            initialTaxHead: q['taxhead'],
            initialFy: q['fy'],
            autoAdd: q['add'] == '1',
          );
        },
      ),
      // Standalone dues view for notification taps ("dues to clear today") and
      // quick actions — own AppBar, optional date filter, optional auto-add.
      GoRoute(
        path: '/dues-day',
        builder: (_, state) {
          final q = state.uri.queryParameters;
          DateTime? date;
          final raw = q['date'];
          if (raw != null) date = DateTime.tryParse(raw);
          return DuesScreen(standalone: true, initialDate: date, autoAdd: q['add'] == '1');
        },
      ),
      GoRoute(path: '/categorize', builder: (_, __) => const CategorizeScreen()),
      GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
      // Statement import wizard (standalone — own AppBar/back, like /txns).
      GoRoute(
        path: '/import',
        builder: (_, state) =>
            ImportScreen(initialAccountId: state.uri.queryParameters['account']),
      ),
      GoRoute(path: '/contacts', builder: (_, __) => const ContactsScreen()),
      GoRoute(
        path: '/contacts/:id',
        builder: (_, state) => ContactDetailScreen(contactId: state.pathParameters['id']!),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(state: state, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(
            path: '/transactions',
            builder: (_, state) {
              final q = state.uri.queryParameters;
              return TransactionsScreen(
                key: ValueKey('txns-${q['account']}-${q['contact']}-${q['category']}-${q['type']}'),
                initialAccount: q['account'],
                initialContact: q['contact'],
                initialCategory: q['category'],
                initialType: q['type'],
              );
            },
          ),
          GoRoute(path: '/dues', builder: (_, __) => const DuesScreen()),
          GoRoute(path: '/debts', builder: (_, __) => const DebtsScreen()),
          GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
        ],
      ),
    ],
  );
}
