import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

class ContactDetailScreen extends StatelessWidget {
  final String contactId;
  const ContactDetailScreen({super.key, required this.contactId});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';

    final contact = data.contactsById[contactId];
    if (contact == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contact')),
        body: const EmptyView(title: 'Contact not found'),
      );
    }

    final position = data.positionOf(contactId);

    final contactTxns = data.transactions.where((t) => t.contactId == contactId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final contactDebts = data.debts.where((d) => d.contactId == contactId).toList();

    final netTone = position.net > 0.005
        ? StatTone.success
        : (position.net < -0.005 ? StatTone.danger : StatTone.neutral);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(title: Text(contact.name)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'Net',
                      amount: position.net,
                      currency: currency,
                      tone: netTone,
                      icon: Icons.balance,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      label: 'In',
                      amount: position.totalIn,
                      currency: currency,
                      tone: StatTone.success,
                      icon: Icons.arrow_downward,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      label: 'Out',
                      amount: position.totalOut,
                      currency: currency,
                      tone: StatTone.danger,
                      icon: Icons.arrow_upward,
                    ),
                  ),
                ],
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Transactions'),
                Tab(text: 'Debts'),
                Tab(text: 'Report'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _transactionsTab(context, data, contactTxns, currency),
                  _debtsTab(data, contactDebts, currency),
                  _reportTab(context, position, contactTxns.length, contactDebts, currency),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transactionsTab(BuildContext context, DataController data, List<Txn> txns, String currency) {
    if (txns.isEmpty) {
      return const EmptyView(title: 'No transactions with this contact');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: txns.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = txns[i];
        final account = data.accountsById[t.accountId]?.name ?? '—';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 2),
          title: Text(t.note?.isNotEmpty == true ? t.note! : account),
          subtitle: Text('${formatDate(t.date)} · $account'),
          trailing: Text(
            formatMoney(t.totalAmount, currency),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: t.totalAmount < 0 ? AppColors.danger : AppColors.accent2,
            ),
          ),
        );
      },
    );
  }

  Widget _debtsTab(DataController data, List<Debt> debts, String currency) {
    if (debts.isEmpty) {
      return const EmptyView(title: 'No debts with this contact');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: debts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final d = debts[i];
        return ListTile(
          title: Text(d.label ?? data.contactsById[d.contactId]?.name ?? 'Debt'),
          subtitle: Text(data.contactsById[d.contactId]?.name ?? '—'),
          trailing: Text(
            formatMoney(data.outstandingOf(d.id), currency),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }

  Widget _reportTab(
    BuildContext context,
    ContactPosition position,
    int txnCount,
    List<Debt> debts,
    String currency,
  ) {
    final openDebts = debts.where((d) => d.status == 'open').length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row(context, 'Transactions', '$txnCount'),
                _row(context, 'Total received', formatMoney(position.totalIn, currency)),
                _row(context, 'Total paid', formatMoney(position.totalOut, currency)),
                _row(context, 'Open debts', '$openDebts'),
                _row(context, 'Net position', formatMoney(position.net, currency)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
