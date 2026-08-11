import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import '../widgets/data_table_view.dart';
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
  'fee': 'Fee',
  'interest_income': 'Interest income',
  'interest_expense': 'Interest expense',
  'tax': 'Tax',
};

class TransactionsScreen extends StatefulWidget {
  /// Optional initial filters — used when navigating in from another screen
  /// (e.g. "View transactions" on an account, category or contact).
  final String? initialAccount;
  final String? initialContact;
  final String? initialCategory;
  final String? initialType;

  /// When true the screen supplies its own AppBar with a back button (used for
  /// the /txns drill-down route). In the bottom-nav shell this is false — the
  /// shell provides the chrome.
  final bool standalone;
  const TransactionsScreen({
    super.key,
    this.initialAccount,
    this.initialContact,
    this.initialCategory,
    this.initialType,
    this.standalone = false,
  });

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String? _accountFilter;
  String? _contactFilter;
  String? _typeFilter;
  String? _categoryFilter;
  bool _splitOnly = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _accountFilter = widget.initialAccount;
    _contactFilter = widget.initialContact;
    _categoryFilter = widget.initialCategory;
    _typeFilter = widget.initialType;
  }

  int get _activeFilterCount =>
      (_accountFilter != null ? 1 : 0) +
      (_contactFilter != null ? 1 : 0) +
      (_typeFilter != null ? 1 : 0) +
      (_categoryFilter != null ? 1 : 0) +
      (_splitOnly ? 1 : 0);

  void _clearFilters() => setState(() {
        _accountFilter = null;
        _contactFilter = null;
        _typeFilter = null;
        _categoryFilter = null;
        _splitOnly = false;
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
                    value: _categoryFilter,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All categories')),
                      for (final c in data.categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => update(() => _categoryFilter = v),
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
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Split transactions only'),
                    value: _splitOnly,
                    onChanged: (v) => update(() => _splitOnly = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            update(() {
                              _accountFilter = null;
                              _contactFilter = null;
                              _typeFilter = null;
                              _categoryFilter = null;
                              _splitOnly = false;
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
    final query = _search.trim().toLowerCase();
    final txns = all.where((t) {
      if (_accountFilter != null && t.accountId != _accountFilter) return false;
      if (_contactFilter != null && t.contactId != _contactFilter) return false;
      if (_categoryFilter != null && !t.lines.any((l) => l.categoryId == _categoryFilter)) return false;
      if (_splitOnly && !t.hasSplit) return false;
      if (_typeFilter != null && !t.lines.any((l) => l.type == _typeFilter)) return false;
      if (query.isNotEmpty) {
        final contactName = t.contactId != null ? data.contactsById[t.contactId]?.name ?? '' : '';
        final hay = '${t.note ?? ''} $contactName'.toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: widget.standalone ? AppBar(title: const Text('Transactions')) : null,
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
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: const InputDecoration(
                hintText: 'Search note / contact…',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                      if (_categoryFilter != null)
                        _chip('Category: ${data.categoriesById[_categoryFilter]?.name ?? 'Unknown'}',
                            () => setState(() => _categoryFilter = null)),
                      if (_typeFilter != null)
                        _chip('Type: ${_kLineTypeLabels[_typeFilter] ?? _typeFilter}',
                            () => setState(() => _typeFilter = null)),
                      if (_splitOnly) _chip('Split only', () => setState(() => _splitOnly = false)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: txns.isEmpty
                ? EmptyView(
                    icon: Icons.receipt_long_outlined,
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
                : DataTableView<Txn>(
                    tableId: 'transactions',
                    rows: txns,
                    onRowTap: (t) => showTransactionDetail(context, t),
                    columns: [
                      DataColumn2<Txn>(
                        key: 'date',
                        label: 'Date',
                        locked: true,
                        defaultWidth: 104,
                        sortValue: (t) => t.date,
                        cell: (t) => Text(formatDate(t.date)),
                      ),
                      DataColumn2<Txn>(
                        key: 'account',
                        label: 'Account',
                        defaultWidth: 140,
                        sortValue: (t) => data.accountsById[t.accountId]?.name ?? '',
                        cell: (t) => Text(data.accountsById[t.accountId]?.name ?? '—', overflow: TextOverflow.ellipsis),
                      ),
                      DataColumn2<Txn>(
                        key: 'contact',
                        label: 'Contact',
                        defaultVisible: false,
                        defaultWidth: 140,
                        cell: (t) => Text(
                            t.contactId != null ? data.contactsById[t.contactId]?.name ?? '—' : '—',
                            overflow: TextOverflow.ellipsis),
                      ),
                      DataColumn2<Txn>(
                        key: 'lines',
                        label: 'Lines',
                        defaultVisible: false,
                        numeric: true,
                        defaultWidth: 68,
                        cell: (t) => Text('${t.lines.length}'),
                      ),
                      DataColumn2<Txn>(
                        key: 'note',
                        label: 'Note',
                        defaultVisible: false,
                        defaultWidth: 170,
                        cell: (t) => Text(t.note ?? '—', overflow: TextOverflow.ellipsis),
                      ),
                      DataColumn2<Txn>(
                        key: 'amount',
                        label: 'Amount',
                        numeric: true,
                        defaultWidth: 120,
                        sortValue: (t) => t.totalAmount,
                        cell: (t) => Text(
                          formatMoney(t.totalAmount, currency),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: t.totalAmount < 0 ? AppColors.danger : AppColors.accent2,
                          ),
                        ),
                      ),
                    ],
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
