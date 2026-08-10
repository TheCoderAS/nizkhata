import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import 'transaction_form.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canCreate = ws.can('transactions.create');
    final txns = [...data.transactions]..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => showTransactionForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Transaction'),
            )
          : null,
      body: txns.isEmpty
          ? EmptyView(
              title: 'No transactions',
              hint: 'Record income, expenses, transfers and debt movements here.',
              action: canCreate
                  ? FilledButton(onPressed: () => showTransactionForm(context), child: const Text('Add transaction'))
                  : null,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: txns.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final t = txns[i];
                final account = data.accountsById[t.accountId]?.name ?? '—';
                final contact = t.contactId != null ? data.contactsById[t.contactId]?.name : null;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 2),
                  title: Text(t.note?.isNotEmpty == true ? t.note! : account),
                  subtitle: Text('${formatDate(t.date)} · $account${contact != null ? ' · $contact' : ''}'),
                  trailing: Text(
                    formatMoney(t.totalAmount, currency),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: t.totalAmount < 0 ? AppColors.danger : AppColors.accent2,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
