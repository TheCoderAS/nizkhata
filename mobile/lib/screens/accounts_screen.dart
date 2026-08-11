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
import '../widgets/data_table_view.dart';
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
              icon: Icons.account_balance_wallet_outlined,
              title: 'No accounts',
              hint: 'Add a cash, bank or card account to record transactions against.',
              action: canManage
                  ? FilledButton(onPressed: () => showAccountForm(context), child: const Text('New account'))
                  : null,
            )
          : DataTableView<Account>(
              tableId: 'accounts',
              rows: accounts,
              onRowTap: canManage ? (a) => showAccountForm(context, existing: a) : null,
              trailing: (a) => PopupMenuButton<String>(
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
              columns: [
                DataColumn2<Account>(
                  key: 'name',
                  label: 'Name',
                  locked: true,
                  defaultWidth: 200,
                  sortValue: (a) => a.name.toLowerCase(),
                  cell: (a) {
                    final masked = a.cardLast4 != null && a.cardLast4!.isNotEmpty
                        ? '···· ${a.cardLast4}'
                        : (a.accountNumber != null && a.accountNumber!.length >= 4
                            ? '···· ${a.accountNumber!.substring(a.accountNumber!.length - 4)}'
                            : '');
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name, overflow: TextOverflow.ellipsis),
                        if (masked.isNotEmpty)
                          Text(
                            masked,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                DataColumn2<Account>(
                  key: 'type',
                  label: 'Type',
                  defaultWidth: 120,
                  sortValue: (a) => _typeLabel(a.type),
                  cell: (a) => Text(_typeLabel(a.type)),
                ),
                DataColumn2<Account>(
                  key: 'opening',
                  label: 'Opening',
                  defaultVisible: false,
                  numeric: true,
                  defaultWidth: 120,
                  sortValue: (a) => a.openingBalance,
                  cell: (a) => Text(formatMoney(a.openingBalance, currency)),
                ),
                DataColumn2<Account>(
                  key: 'balance',
                  label: 'Balance',
                  numeric: true,
                  defaultWidth: 130,
                  sortValue: (a) => data.balanceOf(a.id),
                  cell: (a) {
                    final bal = data.balanceOf(a.id);
                    return Text(
                      accountBalanceLabel(a.type, bal, currency),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: bal < 0 ? AppColors.danger : null,
                      ),
                    );
                  },
                ),
              ],
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
