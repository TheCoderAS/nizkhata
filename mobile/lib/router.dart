import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/contacts_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/debts_screen.dart';
import 'screens/dues_screen.dart';
import 'screens/login_screen.dart';
import 'screens/more_screen.dart';
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
      ShellRoute(
        builder: (context, state, child) => AppShell(state: state, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/transactions', builder: (_, __) => const TransactionsScreen()),
          GoRoute(path: '/dues', builder: (_, __) => const DuesScreen()),
          GoRoute(path: '/debts', builder: (_, __) => const DebtsScreen()),
          GoRoute(path: '/contacts', builder: (_, __) => const ContactsScreen()),
          GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
        ],
      ),
    ],
  );
}
