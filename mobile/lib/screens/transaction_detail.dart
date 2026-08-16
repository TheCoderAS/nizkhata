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
import '../widgets/revision_history.dart';
import 'debt_detail.dart';
import 'due_detail.dart';
import 'split_transaction_form.dart';


/// Read-only detail sheet for a transaction. Lists each line and the total,
/// with Edit (single-line only) / Delete actions in the footer. Mirrors the
/// web TransactionDetailDialog.
Future<void> showTransactionDetail(BuildContext context, Txn txn) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Use the sheet's OWN context (ctx) for MediaQuery — not the caller's, which
    // may already be unmounted (e.g. when re-opened right after another sheet
    // pops), which would blank the sheet.
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
            _row(context, 'Financial year', txn.financialYear),
            if (txn.note?.isNotEmpty == true) _row(context, 'Note', txn.note!),
            _linkedRow(context, data),
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
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            RevisionHistory(entityType: 'transactions', entityId: txn.id),
            const SizedBox(height: 16),
            // A transaction created by settling a due is owned by that due — it
            // can't be edited directly; the due is the source of truth.
            if (canEdit && txn.dueId != null) ...[
              _dueLinkedNote(context),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                if (canEdit)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      // Disabled for due-linked transactions (see note above).
                      onPressed: txn.dueId != null
                          ? null
                          : () {
                              // Pop this sheet, then open the edit form on the still-
                              // mounted navigator context (not this sheet's, which is
                              // being disposed) so the form never opens off a dead context.
                              final nav = Navigator.of(context);
                              final rootContext = nav.context;
                              nav.pop();
                              showSplitTransactionForm(rootContext, existing: txn);
                            },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                if (canEdit && canDelete) const SizedBox(width: 12),
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

  /// Educational banner shown when the transaction was settled from a due — its
  /// fields are owned by the due, so it can't be edited here.
  Widget _dueLinkedNote(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This transaction was created by settling a due, so it can’t be '
              'edited here. Open the linked due and edit it — your changes flow '
              'back to this transaction.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  /// "Linked to" chips: a linked due and any debts referenced by the lines.
  /// Tapping opens that entity's DETAIL sheet in place (no bounce to the list
  /// screen); the list is only a fallback when the entity isn't loaded.
  Widget _linkedRow(BuildContext context, DataController data) {
    final cs = Theme.of(context).colorScheme;
    final chips = <Widget>[];

    if (txn.dueId != null) {
      Due? due;
      for (final d in data.dues) {
        if (d.id == txn.dueId) {
          due = d;
          break;
        }
      }
      final d = due;
      chips.add(_linkChip(
        context,
        'Due · ${d?.title ?? '—'}',
        (root) => d != null ? showDueDetail(root, d) : root.push('/dues'),
      ));
    }
    final debtIds = <String>{
      for (final l in txn.lines)
        if (l.debtId != null) l.debtId!,
    };
    for (final id in debtIds) {
      final debt = data.debtsById[id];
      final label = debt?.label ?? (debt != null ? data.contactsById[debt.contactId]?.name : null) ?? '—';
      chips.add(_linkChip(
        context,
        'Debt · $label',
        (root) => debt != null ? showDebtDetail(root, debt) : root.push('/debts'),
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text('Linked to', style: TextStyle(color: cs.onSurfaceVariant))),
          Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
        ],
      ),
    );
  }

  Widget _linkChip(BuildContext context, String label, void Function(BuildContext root) onOpen) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        // Close this sheet, then open the linked entity's detail on the still-
        // mounted navigator context (this sheet's context is being disposed).
        final nav = Navigator.of(context);
        final root = nav.context;
        nav.pop();
        onOpen(root);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer)),
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
    } else if (line.toAccountId != null) {
      // transfer_in carries the counter (destination) account.
      final to = data.accountsById[line.toAccountId]?.name;
      if (to != null) detail = '→ $to';
    }
    final isTaxable = line.tax?['taxable'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(_lineLabel(line.type))),
                    if (line.external) ...[
                      const SizedBox(width: 6),
                      _badge(context, 'external'),
                    ],
                    if (isTaxable) ...[
                      const SizedBox(width: 6),
                      _badge(context, 'tax'),
                    ],
                  ],
                ),
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

  Widget _badge(BuildContext context, String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
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
