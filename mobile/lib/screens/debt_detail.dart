import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/revision_history.dart';
import 'debt_form.dart';
import 'transaction_detail.dart';
import 'debts_screen.dart';
import '../widgets/common.dart';

const _kPurposeLabels = <String, String>{
  'loan': 'Loan',
  'custodial_savings': 'Custodial savings',
  'lending': 'Lending',
  'reimbursable': 'Reimbursable',
  'informal': 'Informal',
  'shared': 'Shared',
};

String _purposeLabel(String p) => _kPurposeLabels[p] ?? p;

/// Read-only detail sheet for a debt. Shows contact, direction, status, amounts
/// and the linked transactions. Mirrors the web DebtDetail dialog.
Future<void> showDebtDetail(BuildContext context, Debt debt) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _DebtDetail(debt: debt),
    ),
  );
}

class _DebtDetail extends StatelessWidget {
  final Debt debt;
  const _DebtDetail({required this.debt});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canManage = ws.can('debts.manage');
    final canTxn = ws.can('transactions.create');
    final outstanding = data.outstandingOf(debt.id);
    final settleable = debt.status == 'open' && outstanding > 0;
    final settleLabel = debt.direction == 'owed' ? 'Record receipt' : 'Record repayment';
    final contactName = data.contactsById[debt.contactId]?.name ?? '—';
    final title = debt.label ?? contactName;
    final linked = data.transactions.where((t) => t.lines.any((l) => l.debtId == debt.id)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleLarge),
                ),
                if (canManage)
                  TextButton.icon(
                    onPressed: () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      showDebtForm(nav.context, existing: debt);
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DetailRow('Contact', contactName),
            DetailRow('Type', debt.direction == 'owed' ? 'Receivable' : 'Payable'),
            DetailRow('Purpose', _purposeLabel(debt.purpose)),
            DetailRow('Status', debt.status),
            DetailRow('Principal', formatMoney(debt.principal, currency)),
            DetailRow('Outstanding', formatMoney(outstanding, currency)),
            if (debt.interestRate != null && debt.interestRate! > 0) ...[
              DetailRow('Interest rate', '${debt.interestRate}% p.a. (simple)'),
              DetailRow(
                'Interest accrued',
                // Estimate on the CURRENT outstanding since interestFrom (or
                // today when unset) — informational, never posted as a txn.
                formatMoney(
                    roundMoney(outstanding *
                        debt.interestRate! /
                        100 *
                        DateTime.now().difference(debt.interestFrom ?? DateTime.now()).inDays /
                        365),
                    currency),
              ),
            ],
            if (debt.note?.isNotEmpty == true) DetailRow('Note', debt.note!),
            if (canTxn && settleable) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    showDebtPayment(nav.context, debt);
                  },
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: Text(settleLabel),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text('Linked transactions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (linked.isEmpty)
              Text('No transactions linked to this debt yet.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
            else
              for (final t in linked) _txnTile(context, data, t, currency),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            RevisionHistory(entityType: 'debts', entityId: debt.id),
          ],
        ),
      ),
    );
  }

  Widget _txnTile(BuildContext context, DataController data, Txn t, String currency) {
    final cs = Theme.of(context).colorScheme;
    final account = data.accountsById[t.accountId]?.name ?? '—';
    // Opens the transaction's detail sheet stacked on top of this one — no
    // bouncing away to the Transactions screen.
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showTransactionDetail(context, t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.note?.isNotEmpty == true ? t.note! : account),
                  Text('${formatDate(t.date)} · $account',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Text(formatMoney(t.totalAmount, currency), style: const TextStyle(fontWeight: FontWeight.w600)),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
