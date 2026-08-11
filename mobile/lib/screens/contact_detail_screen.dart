import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

const _purposeLabels = <String, String>{
  'loan': 'Loans',
  'custodial_savings': 'Custodial savings',
  'lending': 'Lendings',
  'reimbursable': 'Reimbursable',
  'informal': 'Informal',
  'shared': 'Shared',
};

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

    final infoBits = [contact.phone, contact.email, contact.address]
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(title: Text(contact.name)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _Badge(contact.type == 'business' ? 'Business' : 'Person'),
                      if (contact.relationship == 'family') _Badge('Family'),
                    ],
                  ),
                  if (infoBits.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      infoBits.join(' · '),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                  _debtsTab(context, data, contactDebts, currency),
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

  Widget _debtsTab(BuildContext context, DataController data, List<Debt> debts, String currency) {
    if (debts.isEmpty) {
      return const EmptyView(title: 'No debts with this contact');
    }
    // Group the contact's debts by purpose, preserving first-seen order.
    final byPurpose = <String, List<Debt>>{};
    for (final d in debts) {
      byPurpose.putIfAbsent(d.purpose, () => []).add(d);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        for (final entry in byPurpose.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              _purposeLabels[entry.key] ?? entry.key,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          for (final d in entry.value)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.label ?? _purposeLabels[d.purpose] ?? 'Debt',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _Badge(
                              d.direction == 'owed' ? 'They owe you' : 'You owe',
                              color: d.direction == 'owed' ? AppColors.accent2 : AppColors.danger,
                            ),
                            _Badge(d.status),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatMoney(data.outstandingOf(d.id), currency),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ],
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

class _Badge extends StatelessWidget {
  final String text;
  final Color? color;
  const _Badge(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? cs.outlineVariant).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: (color ?? cs.outlineVariant).withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
