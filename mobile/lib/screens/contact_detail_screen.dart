import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import 'transaction_detail.dart';

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

    final canViewTxns = ws.can('transactions.view');

    // Emails render with their label (e.g. "Personal: a@b.com"); fall back to
    // the legacy single email when no array is present.
    final emailBits = contact.emails.isNotEmpty
        ? contact.emails.map((e) => '${e.label}: ${e.value}').toList()
        : (contact.email != null && contact.email!.isNotEmpty
            ? [contact.email!]
            : <String>[]);
    final infoBits = [
      if (contact.phone != null && contact.phone!.isNotEmpty) contact.phone!,
      ...emailBits,
      if (contact.address != null && contact.address!.isNotEmpty) contact.address!,
    ];

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(contact.name),
          actions: [
            if (canViewTxns)
              IconButton(
                tooltip: 'Open in Transactions',
                icon: const Icon(Icons.swap_horiz),
                onPressed: () => context.push('/transactions?contact=$contactId'),
              ),
          ],
        ),
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
    // Chat-style: oldest -> newest, with a date separator between different days.
    final ordered = [...txns]..sort((a, b) => a.date.compareTo(b.date));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: ordered.length,
      itemBuilder: (context, i) {
        final t = ordered[i];
        final day = formatDate(t.date);
        final showSep = i == 0 || formatDate(ordered[i - 1].date) != day;
        // Money received (>= 0) reads as incoming -> left; paid out -> right.
        final incoming = t.totalAmount >= 0;
        final debtLabels = t.lines
            .where((l) => l.debtId != null)
            .map((l) => data.debtsById[l.debtId]?.label)
            .whereType<String>()
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSep) _dateSeparator(context, day),
            Align(
              alignment: incoming ? Alignment.centerLeft : Alignment.centerRight,
              child: _txnBubble(context, t, currency, incoming, debtLabels),
            ),
          ],
        );
      },
    );
  }

  Widget _dateSeparator(BuildContext context, String day) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            day,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _txnBubble(BuildContext context, Txn t, String currency, bool incoming,
      List<String> debtLabels) {
    final cs = Theme.of(context).colorScheme;
    final amountColor = incoming ? AppColors.accent2 : AppColors.danger;
    final sign = incoming ? '+' : '−';
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      child: Material(
        color: incoming
            ? cs.surfaceContainerHigh
            : cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(incoming ? 4 : 16),
          topRight: Radius.circular(incoming ? 16 : 4),
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(16),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showTransactionDetail(context, t),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$sign${formatMoney(t.totalAmount.abs(), currency)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: amountColor,
                  ),
                ),
                if (t.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(t.note!,
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ],
                if (t.lines.isNotEmpty || debtLabels.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final l in t.lines.take(3)) _MiniBadge(_lineTypeLabel(l.type)),
                      for (final label in debtLabels)
                        _MiniBadge(label, color: AppColors.accent2),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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

const _lineTypeLabels = <String, String>{
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

String _lineTypeLabel(String type) => _lineTypeLabels[type] ?? type;

/// Compact pill used inside chat bubbles for line types / debt labels.
class _MiniBadge extends StatelessWidget {
  final String text;
  final Color? color;
  const _MiniBadge(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = color ?? cs.outlineVariant;
    final fg = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: base.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
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
