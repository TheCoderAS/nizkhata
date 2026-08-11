import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/data_controller.dart';
import '../state/workspace_controller.dart';

class AppShell extends StatefulWidget {
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

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime? _lastBackAt;

  int get _index {
    final loc = widget.state.matchedLocation;
    final i = AppShell._tabs.indexWhere((t) => loc.startsWith(t.$1));
    return i < 0 ? 0 : i;
  }

  // Android back on a tab: from any tab return to Home first; on Home, require a
  // second press within 2s to actually exit (so back never exits unexpectedly).
  void _handleBack() {
    if (_index != 0) {
      context.go('/dashboard');
      return;
    }
    final now = DateTime.now();
    if (_lastBackAt != null && now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Press back again to exit'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final data = context.watch<DataController>();
    final title = ws.activeWorkspace?.name ?? 'NizKhata';
    return PopScope(
      // We manage back ourselves (tab → Home, Home → double-press exit).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          centerTitle: false,
        ),
        body: (ws.loading || data.loading)
            ? const Center(child: CircularProgressIndicator())
            : widget.child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => context.go(AppShell._tabs[i].$1),
          destinations: [
            for (final t in AppShell._tabs)
              NavigationDestination(
                icon: Icon(t.$2),
                selectedIcon: Icon(t.$3),
                label: t.$4,
              ),
          ],
        ),
      ),
    );
  }
}
