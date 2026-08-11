import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import '../widgets/data_table_view.dart';
import 'due_detail.dart';
import 'due_form.dart';

// Status filter values map to sentinels; '__unsettled' is the default view
// (open + partial), '__all' shows every status. Others match a single status.
const _kDueStatusFilters = <String, String>{
  '__unsettled': 'Unsettled',
  'open': 'Open',
  'partial': 'Partial',
  'settled': 'Settled',
  'cancelled': 'Cancelled',
  '__all': 'All statuses',
};

const _kDueDirectionFilters = <String, String>{
  '__all': 'All directions',
  'payable': 'Payable',
  'receivable': 'Receivable',
};

class DuesScreen extends StatefulWidget {
  const DuesScreen({super.key});

  @override
  State<DuesScreen> createState() => _DuesScreenState();
}

class _DuesScreenState extends State<DuesScreen> {
  String _statusFilter = '__unsettled';
  String _directionFilter = '__all';
  String _search = '';

  int get _activeFilterCount =>
      (_statusFilter != '__unsettled' ? 1 : 0) + (_directionFilter != '__all' ? 1 : 0);

  void _clearFilters() => setState(() {
        _statusFilter = '__unsettled';
        _directionFilter = '__all';
      });

  Future<void> _openFilters(BuildContext context) async {
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
                    value: _statusFilter,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      for (final e in _kDueStatusFilters.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => update(() => _statusFilter = v ?? '__unsettled'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _directionFilter,
                    decoration: const InputDecoration(labelText: 'Direction'),
                    items: [
                      for (final e in _kDueDirectionFilters.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => update(() => _directionFilter = v ?? '__all'),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => update(() {
                            _statusFilter = '__unsettled';
                            _directionFilter = '__all';
                          }),
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
    final canManage = ws.can('dues.manage');
    final canTxn = ws.can('transactions.create');
    final canViewContacts = ws.can('contacts.view');
    final canViewTxns = ws.can('transactions.view');

    var receivable = 0.0;
    var payable = 0.0;
    for (final d in data.dues) {
      if (d.status == 'cancelled') continue;
      final remaining = d.amount - data.settledOf(d.id);
      if (remaining <= 0.005) continue;
      if (d.direction == 'receivable') {
        receivable += remaining;
      } else {
        payable += remaining;
      }
    }

    // Apply search + status + direction filters. Default view is unsettled
    // (open + partial); status derives from the settled amount. Search matches
    // title and contact name (case-insensitive).
    final query = _search.trim().toLowerCase();
    final filtered = data.dues.where((d) {
      if (_directionFilter != '__all' && d.direction != _directionFilter) return false;
      if (_statusFilter != '__all') {
        final st = dueStatusFromSettled(d, data.settledOf(d.id));
        if (_statusFilter == '__unsettled') {
          if (st != 'open' && st != 'partial') return false;
        } else if (st != _statusFilter) {
          return false;
        }
      }
      if (query.isNotEmpty) {
        final contactName =
            d.contactId != null ? data.contactsById[d.contactId]?.name ?? '' : '';
        final hay = '${d.title} $contactName'.toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => showDueForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Due'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (receivable > 0 || payable > 0) ...[
                  Row(
                    children: [
                      if (receivable > 0)
                        Expanded(child: StatCard(label: 'Receivable', amount: receivable, currency: currency, tone: StatTone.success, icon: Icons.arrow_downward)),
                      if (receivable > 0 && payable > 0) const SizedBox(width: 12),
                      if (payable > 0)
                        Expanded(child: StatCard(label: 'Payable', amount: payable, currency: currency, tone: StatTone.danger, icon: Icons.arrow_upward)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(
                    hintText: 'Search dues…',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
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
                          if (_statusFilter != '__unsettled')
                            _chip('Status: ${_kDueStatusFilters[_statusFilter]}',
                                () => setState(() => _statusFilter = '__unsettled')),
                          if (_directionFilter != '__all')
                            _chip('Direction: ${_kDueDirectionFilters[_directionFilter]}',
                                () => setState(() => _directionFilter = '__all')),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: EmptyView(
                      icon: (_activeFilterCount > 0 || query.isNotEmpty)
                          ? Icons.filter_alt_off
                          : Icons.call_received,
                      title: (_activeFilterCount > 0 || query.isNotEmpty)
                          ? 'No dues match the filter'
                          : 'No unsettled dues',
                      action: _activeFilterCount > 0
                          ? FilledButton(onPressed: _clearFilters, child: const Text('Clear filters'))
                          : null,
                    ),
                  )
                : DataTableView<Due>(
                    tableId: 'dues',
                    rows: filtered,
                    onRowTap: (d) => showDueDetail(context, d),
                    trailing: (d) => (canManage || canTxn || canViewContacts || canViewTxns)
                        ? _DueMenu(
                            due: d,
                            canManage: canManage,
                            canTxn: canTxn,
                            canViewContacts: canViewContacts,
                            canViewTxns: canViewTxns,
                          )
                        : const SizedBox.shrink(),
                    columns: [
                      DataColumn2<Due>(
                        key: 'title',
                        label: 'Title',
                        locked: true,
                        defaultWidth: 160,
                        sortValue: (d) => d.title,
                        cell: (d) => Text(d.title, overflow: TextOverflow.ellipsis),
                      ),
                      DataColumn2<Due>(
                        key: 'direction',
                        label: 'Direction',
                        defaultVisible: false,
                        defaultWidth: 110,
                        sortValue: (d) => d.direction,
                        cell: (d) => Text(d.direction == 'receivable' ? 'Receivable' : 'Payable'),
                      ),
                      DataColumn2<Due>(
                        key: 'contact',
                        label: 'Contact',
                        defaultVisible: false,
                        defaultWidth: 140,
                        sortValue: (d) => d.contactId != null ? data.contactsById[d.contactId]?.name ?? '' : '',
                        cell: (d) => Text(
                            d.contactId != null ? data.contactsById[d.contactId]?.name ?? '—' : '—',
                            overflow: TextOverflow.ellipsis),
                      ),
                      DataColumn2<Due>(
                        key: 'dueDate',
                        label: 'Due date',
                        defaultWidth: 110,
                        sortValue: (d) => d.dueDate,
                        cell: (d) => Text(formatDate(d.dueDate)),
                      ),
                      DataColumn2<Due>(
                        key: 'amount',
                        label: 'Amount',
                        numeric: true,
                        defaultWidth: 120,
                        sortValue: (d) => d.amount,
                        cell: (d) => Text(formatMoney(d.amount, currency),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      DataColumn2<Due>(
                        key: 'settled',
                        label: 'Settled',
                        defaultVisible: false,
                        numeric: true,
                        defaultWidth: 120,
                        sortValue: (d) => data.settledOf(d.id),
                        cell: (d) => Text(formatMoney(data.settledOf(d.id), currency)),
                      ),
                      DataColumn2<Due>(
                        key: 'status',
                        label: 'Status',
                        defaultWidth: 100,
                        sortValue: (d) => dueStatusFromSettled(d, data.settledOf(d.id)),
                        cell: (d) => Text(dueStatusFromSettled(d, data.settledOf(d.id))),
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

class _DueMenu extends StatelessWidget {
  final Due due;
  final bool canManage;
  final bool canTxn;
  final bool canViewContacts;
  final bool canViewTxns;
  const _DueMenu({
    required this.due,
    required this.canManage,
    required this.canTxn,
    required this.canViewContacts,
    required this.canViewTxns,
  });

  @override
  Widget build(BuildContext context) {
    final data = context.read<DataController>();
    final status = dueStatusFromSettled(due, data.settledOf(due.id));
    final settleable = status == 'open' || status == 'partial';
    final canCancel = status != 'settled' && status != 'cancelled';
    final hasContact = due.contactId != null;
    return PopupMenuButton<String>(
      onSelected: (v) {
        switch (v) {
          case 'pay':
            showDuePayment(context, due);
            break;
          case 'contact':
            if (due.contactId != null) context.push('/contacts/${due.contactId}');
            break;
          case 'txns':
            if (due.contactId != null) {
              context.push('/transactions?contact=${due.contactId}');
            }
            break;
          case 'edit':
            showDueForm(context, existing: due);
            break;
          case 'cancel':
            _cancelDue(context, due);
            break;
          case 'delete':
            _confirmDelete(context, due);
            break;
        }
      },
      itemBuilder: (_) => [
        if (canTxn && settleable) const PopupMenuItem(value: 'pay', child: Text('Record payment')),
        if (canViewContacts && hasContact) const PopupMenuItem(value: 'contact', child: Text('View contact')),
        if (canViewTxns && hasContact) const PopupMenuItem(value: 'txns', child: Text('View transactions')),
        if (canManage) const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (canManage && canCancel) const PopupMenuItem(value: 'cancel', child: Text('Cancel due')),
        if (canManage) const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

Future<void> _cancelDue(BuildContext context, Due due) async {
  final ws = context.read<WorkspaceController>().activeWorkspaceId;
  final user = context.read<AuthController>().user;
  if (ws == null || user == null) return;
  try {
    await Mutations(Actor.fromUser(user)).updateDue(ws, due.id, {'status': 'cancelled'});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Due cancelled')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
    }
  }
}

void _confirmDelete(BuildContext context, Due due) {
  final ws = context.read<WorkspaceController>().activeWorkspaceId;
  final user = context.read<AuthController>().user;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${due.title}"?'),
      content: const Text('This removes the due. Any transactions recorded against it are kept.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            if (ws == null || user == null) return;
            try {
              await Mutations(Actor.fromUser(user)).deleteDue(ws, due.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Due deleted')));
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

Future<void> showDuePayment(BuildContext context, Due due) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _DuePaymentSheet(due: due),
    ),
  );
}

class _DuePaymentSheet extends StatefulWidget {
  final Due due;
  const _DuePaymentSheet({required this.due});
  @override
  State<_DuePaymentSheet> createState() => _DuePaymentSheetState();
}

class _DuePaymentSheetState extends State<_DuePaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  String? _accountId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final data = context.read<DataController>();
    final remaining = widget.due.amount - data.settledOf(widget.due.id);
    _amount = TextEditingController(text: (remaining > 0 ? remaining : 0).toString());
    _accountId = widget.due.accountId;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) return;
    final wsC = context.read<WorkspaceController>();
    final ws = wsC.activeWorkspaceId;
    final fyStart = wsC.activeWorkspace?.fyStartMonth ?? 4;
    final user = context.read<AuthController>().user;
    final data = context.read<DataController>();
    if (ws == null || user == null) return;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) return;

    final due = widget.due;
    final now = DateTime.now();
    final lid = now.microsecondsSinceEpoch;
    final newSettled = data.settledOf(due.id) + amount;
    setState(() => _busy = true);
    try {
      await Mutations(Actor.fromUser(user)).settleDue(
        ws,
        due.id,
        date: now,
        note: due.title,
        accountId: _accountId!,
        contactId: due.contactId,
        totalAmount: roundMoney(due.direction == 'payable' ? -amount : amount),
        financialYear: financialYearOf(now, fyStart),
        lines: [
          {
            'lineId': 'due_$lid',
            'type': due.direction == 'payable' ? 'expense' : 'income',
            'amount': amount,
          },
        ],
        newStatus: dueStatusFromSettled(due, newSettled),
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment recorded')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final accounts = data.accounts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Record payment: ${widget.due.title}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => (double.tryParse(v?.trim() ?? '') ?? 0) <= 0 ? 'Enter an amount' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _accountId,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                onChanged: (v) => setState(() => _accountId = v),
                validator: (v) => v == null ? 'Pick an account' : null,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy || accounts.isEmpty ? null : _save,
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(accounts.isEmpty ? 'Add an account first' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
