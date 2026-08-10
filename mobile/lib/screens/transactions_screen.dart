import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import 'split_transaction_form.dart';
import 'transaction_detail.dart';
import 'transaction_form.dart';

const _kLineTypeLabels = <String, String>{
  'income': 'Income',
  'expense': 'Expense',
  'transfer_out': 'Transfer out',
  'transfer_in': 'Transfer in',
  'borrow': 'Borrow',
  'lend': 'Lend',
  'repayment': 'Repayment',
};

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String? _accountFilter;
  String? _contactFilter;
  String? _typeFilter;

  int get _activeFilterCount =>
      (_accountFilter != null ? 1 : 0) + (_contactFilter != null ? 1 : 0) + (_typeFilter != null ? 1 : 0);

  void _clearFilters() => setState(() {
        _accountFilter = null;
        _contactFilter = null;
        _typeFilter = null;
      });

  Future<void> _openAddMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Quick entry'),
              subtitle: const Text('A single expense, income, transfer or debt movement.'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                showTransactionForm(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.call_split),
              title: const Text('Split (multi-line)'),
              subtitle: const Text('Several typed lines in one transaction.'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                showSplitTransactionForm(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilters(BuildContext context) async {
    final data = context.read<DataController>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            void update(VoidCallback fn) {
              setSheet(fn);
              setState(fn);
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filters', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _accountFilter,
                    decoration: const InputDecoration(labelText: 'Account'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All accounts')),
                      for (final a in data.accounts) DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => update(() => _accountFilter = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _contactFilter,
                    decoration: const InputDecoration(labelText: 'Contact'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All contacts')),
                      for (final c in data.contacts) DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => update(() => _contactFilter = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _typeFilter,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All types')),
                      for (final e in _kLineTypeLabels.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => update(() => _typeFilter = v),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            update(() {
                              _accountFilter = null;
                              _contactFilter = null;
                              _typeFilter = null;
                            });
                          },
                          child: const Text('Clear all'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canCreate = ws.can('transactions.create');
    final all = [...data.transactions]..sort((a, b) => b.date.compareTo(a.date));
    final txns = all.where((t) {
      if (_accountFilter != null && t.accountId != _accountFilter) return false;
      if (_contactFilter != null && t.contactId != _contactFilter) return false;
      if (_typeFilter != null && !t.lines.any((l) => l.type == _typeFilter)) return false;
      return true;
    }).toList();

    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _openAddMenu(context),
              icon: const Icon(Icons.add),
              label: const Text('Transaction'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openFilters(context),
                  icon: const Icon(Icons.filter_list, size: 18),
                  label: Text(_activeFilterCount > 0 ? 'Filters ($_activeFilterCount)' : 'Filters'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (_accountFilter != null)
                        _chip('Account: ${data.accountsById[_accountFilter]?.name ?? 'Unknown'}',
                            () => setState(() => _accountFilter = null)),
                      if (_contactFilter != null)
                        _chip('Contact: ${data.contactsById[_contactFilter]?.name ?? 'Unknown'}',
                            () => setState(() => _contactFilter = null)),
                      if (_typeFilter != null)
                        _chip('Type: ${_kLineTypeLabels[_typeFilter] ?? _typeFilter}',
                            () => setState(() => _typeFilter = null)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: txns.isEmpty
                ? EmptyView(
                    title: 'No transactions',
                    hint: _activeFilterCount > 0
                        ? 'Try clearing filters.'
                        : 'Record income, expenses, transfers and debt movements here.',
                    action: _activeFilterCount > 0
                        ? FilledButton(onPressed: _clearFilters, child: const Text('Clear filters'))
                        : (canCreate
                            ? FilledButton(
                                onPressed: () => showTransactionForm(context),
                                child: const Text('Add transaction'))
                            : null),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: txns.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final t = txns[i];
                      final account = data.accountsById[t.accountId]?.name ?? '—';
                      final contact = t.contactId != null ? data.contactsById[t.contactId]?.name : null;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 2),
                        onTap: () => showTransactionDetail(context, t),
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
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, VoidCallback onClear) {
    return InputChip(
      label: Text(label),
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close, size: 16),
    );
  }
}
