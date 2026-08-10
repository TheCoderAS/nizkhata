import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import 'transaction_form.dart';

/// Read-only detail sheet for a transaction. Lists each line and the total,
/// with Edit (single-line only) / Delete actions in the footer. Mirrors the
/// web TransactionDetailDialog.
Future<void> showTransactionDetail(BuildContext context, Txn txn) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _TransactionDetail(txn: txn),
    ),
  );
}

const _kLineLabels = <String, String>{
  'income': 'Income',
  'expense': 'Expense',
  'transfer_out': 'Transfer out',
  'transfer_in': 'Transfer in',
  'borrow': 'Borrow',
  'lend': 'Lend',
  'repayment': 'Repayment',
  'fee': 'Fee',
  'interest_income': 'Interest income',
  'interest_expense': 'Interest expense',
  'tax': 'Tax',
};

String _lineLabel(String type) => _kLineLabels[type] ?? type;

class _TransactionDetail extends StatelessWidget {
  final Txn txn;
  const _TransactionDetail({required this.txn});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canEdit = ws.can('transactions.edit');
    final canDelete = ws.can('transactions.delete');
    final account = data.accountsById[txn.accountId]?.name ?? '—';
    final contact = txn.contactId != null ? data.contactsById[txn.contactId]?.name : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transaction', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _row(context, 'Date', formatDate(txn.date)),
            _row(context, 'Account', account),
            if (contact != null) _row(context, 'Contact', contact),
            if (txn.note?.isNotEmpty == true) _row(context, 'Note', txn.note!),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            for (final line in txn.lines) _lineTile(context, data, line, currency),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  formatMoney(txn.totalAmount, currency),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: txn.totalAmount < 0 ? AppColors.danger : AppColors.accent2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (canEdit && txn.lines.length == 1)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        showTransactionForm(context, existing: txn);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                if (canEdit && txn.lines.length == 1 && canDelete) const SizedBox(width: 12),
                if (canDelete)
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                      onPressed: () => _confirmDelete(context, txn),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: TextStyle(color: cs.onSurfaceVariant))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _lineTile(BuildContext context, DataController data, TxnLine line, String currency) {
    final cs = Theme.of(context).colorScheme;
    String? detail;
    if (line.categoryId != null) {
      detail = data.categoriesById[line.categoryId]?.name;
    } else if (line.debtId != null) {
      final debt = data.debtsById[line.debtId];
      detail = debt?.label ?? (debt != null ? data.contactsById[debt.contactId]?.name : null);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_lineLabel(line.type)),
                if (detail != null)
                  Text(detail, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Text(formatMoney(line.amount, currency),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

void _confirmDelete(BuildContext context, Txn txn) {
  final ws = context.read<WorkspaceController>().activeWorkspaceId;
  final user = context.read<AuthController>().user;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete transaction?'),
      content: const Text('This removes the entry and its effect on balances and reports.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            if (ws == null || user == null) return;
            try {
              await Mutations(Actor.fromUser(user)).deleteTransaction(ws, txn.id);
              if (context.mounted) {
                Navigator.of(context).pop(); // close the detail sheet
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Transaction deleted')));
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
