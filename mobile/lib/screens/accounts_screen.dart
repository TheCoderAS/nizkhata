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
import '../widgets/entity_card_list.dart';
import '../widgets/revision_history.dart';
import 'account_form.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canManage = ws.can('accounts.manage');
    final canViewTxns = ws.can('transactions.view');
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
          : EntityCardList<Account>(
              listId: 'accounts',
              rows: accounts,
              onRowTap: (a) => showAccountDetail(context, a),
              leading: (a) => _AccountBadge(type: a.type),
              trailing: (a) => PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'ledger') context.push('/accounts/${a.id}/ledger');
                  if (v == 'transactions') context.push('/txns?account=${a.id}');
                  if (v == 'edit') showAccountForm(context, existing: a);
                  if (v == 'delete') _confirmDelete(context, a);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'ledger', child: Text('View ledger')),
                  if (canViewTxns) const PopupMenuItem(value: 'transactions', child: Text('View transactions')),
                  if (canManage) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (canManage) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
              fields: [
                CardField<Account>(
                  key: 'name',
                  label: 'Name',
                  role: CardRole.title,
                  locked: true,
                  sortValue: (a) => a.name.toLowerCase(),
                  text: (a) => a.name,
                ),
                CardField<Account>(
                  key: 'number',
                  label: 'Number',
                  icon: Icons.tag,
                  sortValue: (a) => _masked(a),
                  text: (a) {
                    final masked = _masked(a);
                    return masked.isEmpty ? '—' : masked;
                  },
                ),
                CardField<Account>(
                  key: 'type',
                  label: 'Type',
                  icon: Icons.label_outline,
                  sortValue: (a) => _typeLabel(a.type),
                  text: (a) => _typeLabel(a.type),
                ),
                CardField<Account>(
                  key: 'opening',
                  label: 'Opening',
                  icon: Icons.savings_outlined,
                  defaultVisible: false,
                  sortValue: (a) => a.openingBalance,
                  text: (a) => formatMoney(a.openingBalance, currency),
                ),
                CardField<Account>(
                  key: 'balance',
                  label: 'Balance',
                  role: CardRole.amount,
                  sortValue: (a) => data.balanceOf(a.id),
                  widget: (a) {
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

  static String _masked(Account a) {
    if (a.cardLast4 != null && a.cardLast4!.isNotEmpty) return '···· ${a.cardLast4}';
    if (a.accountNumber != null && a.accountNumber!.length >= 4) {
      return '····${a.accountNumber!.substring(a.accountNumber!.length - 4)}';
    }
    return '';
  }

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

// Read-only account detail sheet. Mirrors the web AccountDetail dialog
// (src/pages/Accounts.tsx): type, opening/current balance, masked identifier and
// any populated metadata, with Edit / View-transactions actions by permission.
// Note: the mobile Account model does not carry audit fields (createdBy/At,
// updatedBy/At), so the web's audit block is omitted here.
void showAccountDetail(BuildContext context, Account a) {
  final data = context.read<DataController>();
  final ws = context.read<WorkspaceController>();
  final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
  final canManage = ws.can('accounts.manage');
  final canViewTxns = ws.can('transactions.view');
  final balance = data.balanceOf(a.id);

  // Populated metadata fields, in the same display order the web uses per type.
  const orderByType = <String, List<String>>{
    'cash': ['code', 'description'],
    'bank': ['accountNumber', 'ifsc', 'cif', 'branchName', 'code', 'description'],
    'credit_card': ['nameOnCard', 'cardLast4', 'cardExpiry', 'code', 'description'],
  };
  const labels = <String, String>{
    'accountNumber': 'Account number',
    'ifsc': 'IFSC code',
    'cif': 'CIF number',
    'branchName': 'Branch name',
    'nameOnCard': 'Name on card',
    'cardLast4': 'Card (last 4)',
    'cardExpiry': 'Expiry',
    'code': 'Code',
    'description': 'Description',
  };
  String? valueOf(String key) {
    switch (key) {
      case 'accountNumber':
        return a.accountNumber;
      case 'ifsc':
        return a.ifsc;
      case 'cif':
        return a.cif;
      case 'branchName':
        return a.branchName;
      case 'nameOnCard':
        return a.nameOnCard;
      case 'cardLast4':
        return a.cardLast4;
      case 'cardExpiry':
        return a.cardExpiry;
      case 'code':
        return a.code;
      case 'description':
        return a.description;
      default:
        return null;
    }
  }

  final meta = <MapEntry<String, String>>[];
  for (final key in orderByType[a.type] ?? const <String>[]) {
    final v = valueOf(key);
    if (v != null && v.trim().isNotEmpty) meta.add(MapEntry(labels[key]!, v.trim()));
  }
  final masked = AccountsScreen._masked(a);

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      final cs = Theme.of(sheetCtx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(a.name, style: Theme.of(sheetCtx).textTheme.titleLarge),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        AccountsScreen._typeLabel(a.type),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                if (masked.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(masked, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ],
                const SizedBox(height: 16),
                _DetailRow(label: 'Opening balance', value: formatMoney(a.openingBalance, currency)),
                _DetailRow(
                  label: 'Current balance',
                  value: accountBalanceLabel(a.type, balance, currency),
                  valueColor: balance < 0 ? AppColors.danger : null,
                ),
                for (final e in meta) _DetailRow(label: e.key, value: e.value),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                RevisionHistory(entityType: 'accounts', entityId: a.id),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (canViewTxns)
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          label: const Text('Transactions'),
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            context.push('/txns?account=${a.id}');
                          },
                        ),
                      ),
                    if (canViewTxns && canManage) const SizedBox(width: 12),
                    if (canManage)
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Edit'),
                          onPressed: () {
                            Navigator.of(sheetCtx).pop();
                            showAccountForm(context, existing: a);
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Colored, type-specific badge shown at the start of each account card.
class _AccountBadge extends StatelessWidget {
  final String type;
  const _AccountBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (type) {
      'cash' => (Icons.payments_outlined, AppColors.accent2),
      'credit_card' => (Icons.credit_card, AppColors.brandTo),
      _ => (Icons.account_balance_outlined, AppColors.brand),
    };
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 21, color: color),
    );
  }
}
