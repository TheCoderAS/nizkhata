import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/data_controller.dart';
import '../state/workspace_controller.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  final GoRouterState state;
  const AppShell({super.key, required this.child, required this.state});

  static const _tabs = [
    ('/dashboard', Icons.dashboard_outlined, Icons.dashboard, 'Home'),
    ('/transactions', Icons.swap_horiz_outlined, Icons.swap_horiz, 'Txns'),
    ('/dues', Icons.receipt_long_outlined, Icons.receipt_long, 'Dues'),
    ('/debts', Icons.handshake_outlined, Icons.handshake, 'Debts'),
    ('/more', Icons.menu, Icons.menu, 'More'),
  ];

  int get _index {
    final loc = state.matchedLocation;
    final i = _tabs.indexWhere((t) => loc.startsWith(t.$1));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final data = context.watch<DataController>();
    final title = ws.activeWorkspace?.name ?? 'NizKhata';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: false,
      ),
      body: (ws.loading || data.loading)
          ? const Center(child: CircularProgressIndicator())
          : child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => context.go(_tabs[i].$1),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.$2),
              selectedIcon: Icon(t.$3),
              label: t.$4,
            ),
        ],
      ),
    );
  }
}
