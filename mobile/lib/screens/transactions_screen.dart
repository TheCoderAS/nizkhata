import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import '../widgets/entity_card_list.dart';
import '../widgets/txn_lines_editor.dart' show kTaxHeads;
import 'split_transaction_form.dart';
import 'transaction_detail.dart';


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
  final String? initialTaxHead;
  final String? initialFy;

  /// Show only this day — the calendar's "view transactions" for a date.
  final DateTime? initialDate;

  /// When true the screen supplies its own AppBar with a back button (used for
  /// the /txns drill-down route). In the bottom-nav shell this is false — the
  /// shell provides the chrome.
  final bool standalone;

  /// Auto-open the "new transaction" form on first build (quick action).
  final bool autoAdd;
  const TransactionsScreen({
    super.key,
    this.initialAccount,
    this.initialContact,
    this.initialCategory,
    this.initialType,
    this.initialTaxHead,
    this.initialFy,
    this.initialDate,
    this.standalone = false,
    this.autoAdd = false,
  });

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String? _accountFilter;
  String? _contactFilter;
  String? _typeFilter;
  String? _categoryFilter;
  // Drill-down-only filters (set via /txns?taxhead=…&fy=… from Reports; shown
  // as removable chips, not in the filter sheet).
  String? _taxHeadFilter;
  String? _fyFilter;
  DateTime? _dateFilter;
  bool _splitOnly = false;
  String _search = '';
  bool _fabOpen = false;

  @override
  void initState() {
    super.initState();
    _accountFilter = widget.initialAccount;
    _contactFilter = widget.initialContact;
    _categoryFilter = widget.initialCategory;
    _typeFilter = widget.initialType;
    _taxHeadFilter = widget.initialTaxHead;
    _fyFilter = widget.initialFy;
    _dateFilter = widget.initialDate;
    if (widget.autoAdd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showSplitTransactionForm(context);
      });
    }
  }

  int get _activeFilterCount =>
      (_accountFilter != null ? 1 : 0) +
      (_contactFilter != null ? 1 : 0) +
      (_typeFilter != null ? 1 : 0) +
      (_categoryFilter != null ? 1 : 0) +
      (_taxHeadFilter != null ? 1 : 0) +
      (_fyFilter != null ? 1 : 0) +
      (_dateFilter != null ? 1 : 0) +
      (_splitOnly ? 1 : 0);

  void _clearFilters() => setState(() {
        _accountFilter = null;
        _contactFilter = null;
        _typeFilter = null;
        _categoryFilter = null;
        _taxHeadFilter = null;
        _fyFilter = null;
        _dateFilter = null;
        _splitOnly = false;
      });

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
      if (_dateFilter != null) {
        final d = _dateFilter!;
        if (t.date.year != d.year || t.date.month != d.month || t.date.day != d.day) {
          return false;
        }
      }
      if (_accountFilter != null && t.accountId != _accountFilter) return false;
      if (_contactFilter != null && t.contactId != _contactFilter) return false;
      if (_categoryFilter != null && !t.lines.any((l) => l.categoryId == _categoryFilter)) return false;
      if (_splitOnly && !t.hasSplit) return false;
      if (_typeFilter != null && !t.lines.any((l) => l.type == _typeFilter)) return false;
      if (_taxHeadFilter != null &&
          !t.lines.any((l) =>
              l.tax != null &&
              l.tax!['taxable'] == true &&
              (l.tax!['head'] ?? 'other') == _taxHeadFilter)) {
        return false;
      }
      if (_fyFilter != null && t.financialYear != _fyFilter) return false;
      if (query.isNotEmpty) {
        final contactName = t.contactId != null ? data.contactsById[t.contactId]?.name ?? '' : '';
        final hay = '${t.note ?? ''} $contactName'.toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: widget.standalone ? AppBar(title: const Text('Transactions')) : null,
      floatingActionButton: canCreate ? _buildFab(context) : null,
      body: Stack(
        children: [
          Column(
            children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: const InputDecoration(
                      hintText: 'Search note / contact…',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
                Gap.sm,
                IconButton.filledTonal(
                  onPressed: () => _openFilters(context),
                  icon: Badge(
                    isLabelVisible: _activeFilterCount > 0,
                    label: Text('$_activeFilterCount'),
                    child: const Icon(Icons.tune),
                  ),
                ),
              ],
            ),
          ),
          if (_activeFilterCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (_dateFilter != null) ...[
                      _chip('Date: ${formatDate(_dateFilter!)}',
                          () => setState(() => _dateFilter = null)),
                      Gap.sm,
                    ],
                    if (_accountFilter != null) ...[
                      _chip('Account: ${data.accountsById[_accountFilter]?.name ?? 'Unknown'}',
                          () => setState(() => _accountFilter = null)),
                      Gap.sm,
                    ],
                    if (_contactFilter != null) ...[
                      _chip('Contact: ${data.contactsById[_contactFilter]?.name ?? 'Unknown'}',
                          () => setState(() => _contactFilter = null)),
                      Gap.sm,
                    ],
                    if (_categoryFilter != null) ...[
                      _chip('Category: ${data.categoriesById[_categoryFilter]?.name ?? 'Unknown'}',
                          () => setState(() => _categoryFilter = null)),
                      Gap.sm,
                    ],
                    if (_typeFilter != null) ...[
                      _chip('Type: ${_kLineTypeLabels[_typeFilter] ?? _typeFilter}',
                          () => setState(() => _typeFilter = null)),
                      Gap.sm,
                    ],
                    if (_taxHeadFilter != null) ...[
                      _chip('Tax head: ${kTaxHeads[_taxHeadFilter] ?? _taxHeadFilter}',
                          () => setState(() => _taxHeadFilter = null)),
                      Gap.sm,
                    ],
                    if (_fyFilter != null) ...[
                      _chip('FY: $_fyFilter', () => setState(() => _fyFilter = null)),
                      Gap.sm,
                    ],
                    if (_splitOnly)
                      _chip('Split only', () => setState(() => _splitOnly = false)),
                  ],
                ),
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
                                onPressed: () => showSplitTransactionForm(context),
                                child: const Text('Add transaction'))
                            : null),
                  )
                : EntityCardList<Txn>(
                    listId: 'transactions',
                    rows: txns,
                    onRowTap: (t) => showTransactionDetail(context, t),
                    fields: [
                      CardField<Txn>(
                        key: 'note',
                        label: 'Note',
                        role: CardRole.title,
                        locked: true,
                        text: (t) => t.note?.isNotEmpty == true ? t.note! : 'Transaction',
                      ),
                      CardField<Txn>(
                        key: 'amount',
                        label: 'Amount',
                        role: CardRole.amount,
                        sortValue: (t) => t.totalAmount,
                        widget: (t) => Text(
                          formatMoney(t.totalAmount, currency),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: t.totalAmount < 0 ? AppColors.danger : AppColors.accent2,
                          ),
                        ),
                      ),
                      CardField<Txn>(
                        key: 'date',
                        label: 'Date',
                        role: CardRole.meta,
                        icon: Icons.event,
                        defaultVisible: true,
                        sortValue: (t) => t.date,
                        text: (t) => formatDate(t.date),
                      ),
                      CardField<Txn>(
                        key: 'account',
                        label: 'Account',
                        role: CardRole.meta,
                        icon: Icons.account_balance_wallet_outlined,
                        defaultVisible: true,
                        sortValue: (t) => data.accountsById[t.accountId]?.name ?? '',
                        text: (t) => data.accountsById[t.accountId]?.name ?? '—',
                      ),
                      CardField<Txn>(
                        key: 'contact',
                        label: 'Contact',
                        role: CardRole.meta,
                        icon: Icons.person_outline,
                        defaultVisible: false,
                        text: (t) => t.contactId != null
                            ? data.contactsById[t.contactId]?.name ?? '—'
                            : '—',
                      ),
                      CardField<Txn>(
                        key: 'lines',
                        label: 'Lines',
                        role: CardRole.meta,
                        icon: Icons.segment,
                        defaultVisible: false,
                        text: (t) => '${t.lines.length}',
                      ),
                    ],
                  ),
          ),
            ],
          ),
          // Tap-outside scrim to dismiss the expanded FAB menu.
          if (_fabOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _fabOpen = false),
                child: const ColoredBox(color: Color(0x55000000)),
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

  /// FAB that expands into two actions: new transaction, or import a statement.
  Widget _buildFab(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabOpen) ...[
          _fabAction(
            icon: Icons.file_upload_outlined,
            label: 'Import statement',
            onTap: () {
              setState(() => _fabOpen = false);
              context.push('/import');
            },
          ),
          const SizedBox(height: 12),
          _fabAction(
            icon: Icons.edit_outlined,
            label: 'New transaction',
            onTap: () {
              setState(() => _fabOpen = false);
              showSplitTransactionForm(context);
            },
          ),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          onPressed: () => setState(() => _fabOpen = !_fabOpen),
          tooltip: _fabOpen ? 'Close' : 'Add',
          child: AnimatedRotation(
            turns: _fabOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 180),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _fabAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: cs.surfaceContainerHighest,
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.small(
          heroTag: 'fab_$label',
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }
}
