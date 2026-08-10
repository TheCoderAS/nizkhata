import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import 'account_form.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canManage = ws.can('accounts.manage');
    final accounts = [...data.accounts]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => showAccountForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Account'),
            )
          : null,
      body: accounts.isEmpty
          ? EmptyView(
              title: 'No accounts',
              hint: 'Add a cash, bank or card account to record transactions against.',
              action: canManage
                  ? FilledButton(onPressed: () => showAccountForm(context), child: const Text('New account'))
                  : null,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: accounts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = accounts[i];
                final bal = data.balanceOf(a.id);
                final masked = a.cardLast4 != null && a.cardLast4!.isNotEmpty
                    ? ' ···· ${a.cardLast4}'
                    : (a.accountNumber != null && a.accountNumber!.length >= 4
                        ? ' ···· ${a.accountNumber!.substring(a.accountNumber!.length - 4)}'
                        : '');
                return ListTile(
                  title: Text(a.name),
                  subtitle: Text('${_typeLabel(a.type)}$masked'),
                  onTap: canManage ? () => showAccountForm(context, existing: a) : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatMoney(bal, currency),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: bal < 0 ? AppColors.danger : null,
                        ),
                      ),
                      if (canManage)
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'ledger') context.push('/accounts/${a.id}/ledger');
                            if (v == 'edit') showAccountForm(context, existing: a);
                            if (v == 'delete') _confirmDelete(context, a);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'ledger', child: Text('View ledger')),
                            if (canManage) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            if (canManage) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  static String _typeLabel(String t) =>
      t == 'cash' ? 'Cash' : (t == 'credit_card' ? 'Credit card' : 'Bank');

  void _confirmDelete(BuildContext context, Account a) {
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    final user = context.read<AuthController>().user;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${a.name}"?'),
        content: const Text('This removes the account. Its transactions are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              if (ws == null || user == null) return;
              try {
                await Mutations(Actor.fromUser(user)).deleteAccount(ws, a.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account deleted')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
