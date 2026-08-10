import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final ws = context.watch<WorkspaceController>();
    final data = context.watch<DataController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final user = auth.user;

    final totalInAccounts = data.accounts.fold<double>(0, (s, a) => s + data.balanceOf(a.id));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
              child: user?.photoURL == null ? Text(initialsOf(user?.displayName ?? user?.email ?? '?')) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user?.displayName ?? 'Signed in',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (user?.email != null)
                    Text(user!.email!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionCard(
          title: 'Workspace',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Name', ws.activeWorkspace?.name ?? '—'),
              _kv('Base currency', currency),
              _kv('Accounts', '${data.accounts.length}'),
              _kv('Total in accounts', formatMoney(totalInAccounts, currency)),
              _kv('Contacts', '${data.contacts.where((c) => c.connectionUid == null).length}'),
              _kv('Transactions', '${data.transactions.length}'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              _navTile(context, Icons.account_balance_wallet_outlined, 'Accounts', '/accounts'),
              const Divider(height: 1),
              _navTile(context, Icons.category_outlined, 'Categories', '/categories'),
              const Divider(height: 1),
              _navTile(context, Icons.savings_outlined, 'Budgets', '/budgets'),
              const Divider(height: 1),
              _navTile(context, Icons.bar_chart_outlined, 'Reports', '/reports'),
              const Divider(height: 1),
              _navTile(context, Icons.history, 'Activity', '/activity'),
            ],
          ),
        ),
        if (ws.workspaces.length > 1) ...[
          const SizedBox(height: 12),
          SectionCard(
            title: 'Switch workspace',
            child: Column(
              children: [
                for (final w in ws.workspaces)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(w.name),
                    trailing: w.id == ws.activeWorkspaceId ? const Icon(Icons.check) : null,
                    onTap: () => ws.switchWorkspace(w.id),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.tonalIcon(
          onPressed: () => auth.signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }

  Widget _navTile(BuildContext context, IconData icon, String title, String route) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(route),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(k), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))],
        ),
      );
}
