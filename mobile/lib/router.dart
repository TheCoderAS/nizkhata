import 'package:go_router/go_router.dart';

import 'screens/account_ledger_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/activity_screen.dart';
import 'screens/budgets_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/contact_detail_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/debts_screen.dart';
import 'screens/dues_screen.dart';
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

GoRouter buildRouter(AuthController auth) {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: auth,
    redirect: (context, state) {
      final signedIn = auth.user != null;
      final loggingIn = state.matchedLocation == '/login';
      if (auth.loading) return null;
      if (!signedIn) return loggingIn ? null : '/login';
      if (loggingIn) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
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
      GoRoute(path: '/contacts', builder: (_, __) => const ContactsScreen()),
      GoRoute(
        path: '/contacts/:id',
        builder: (_, state) => ContactDetailScreen(contactId: state.pathParameters['id']!),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(state: state, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/transactions', builder: (_, __) => const TransactionsScreen()),
          GoRoute(path: '/dues', builder: (_, __) => const DuesScreen()),
          GoRoute(path: '/debts', builder: (_, __) => const DebtsScreen()),
          GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
        ],
      ),
    ],
  );
}
