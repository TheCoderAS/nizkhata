import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../services/khata_pdf.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/revision_history.dart';
import 'due_form.dart';
import 'transaction_detail.dart';
import 'dues_screen.dart';
import '../widgets/common.dart';

/// Read-only detail sheet for a due. Shows direction, status, amounts and the
/// linked payment transactions. Mirrors the web DueDetail dialog.
Future<void> showDueDetail(BuildContext context, Due due) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _DueDetail(due: due),
    ),
  );
}

class _DueDetail extends StatelessWidget {
  final Due due;
  const _DueDetail({required this.due});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canManage = ws.can('dues.manage');
    final canTxn = ws.can('transactions.create');
    final settled = data.settledOf(due.id);
    final status = dueStatusFromSettled(due, settled);
    final settleable = status == 'open' || status == 'partial';
    final remaining = due.amount - settled;
    final contact = due.contactId != null ? data.contactsById[due.contactId]?.name : null;
    final account = due.accountId != null ? data.accountsById[due.accountId]?.name : null;
    final linked = data.transactions.where((t) => t.dueId == due.id).toList()
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
                  child: Text(due.title, style: Theme.of(context).textTheme.titleLarge),
                ),
                if (canManage)
                  TextButton.icon(
                    onPressed: () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      showDueForm(nav.context, existing: due);
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DetailRow('Direction', due.direction == 'receivable' ? 'Receivable' : 'Payable'),
            DetailRow('Status', status),
            DetailRow('Due date', formatDate(due.dueDate)),
            DetailRow('Amount', formatMoney(due.amount, currency)),
            DetailRow('Settled', formatMoney(settled, currency)),
            DetailRow('Remaining', formatMoney(remaining > 0 ? remaining : 0, currency)),
            if (contact != null) DetailRow('Contact', contact),
            if (account != null) DetailRow('Account', account),
            if (canTxn && settleable) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    showDuePayment(nav.context, due);
                  },
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Record payment'),
                ),
              ),
            ],
            if (settleable && contact != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Share.share(buildDueReminderText(
                    contactName: contact,
                    dueTitle: due.title,
                    remaining: roundMoney(remaining > 0 ? remaining : 0),
                    dueDate: due.dueDate,
                    currency: currency,
                    direction: due.direction,
                  )),
                  icon: const Icon(Icons.notifications_active_outlined, size: 18),
                  label: const Text('Send reminder'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text('Linked transactions',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (linked.isEmpty)
              Text('No payments recorded yet.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
            else
              for (final t in linked) _txnTile(context, data, t, currency),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            RevisionHistory(entityType: 'dues', entityId: due.id),
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
            Text(formatMoney(t.totalAmount, currency),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
