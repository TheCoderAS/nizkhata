import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/due_settlement.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../services/khata_pdf.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import '../widgets/entity_card_list.dart';
import '../widgets/discard_guard.dart';
import '../widgets/row_actions.dart';
import '../widgets/undo_delete.dart';
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
  /// Standalone mode (own AppBar + back button) — used by the /dues-day
  /// drill-down route (notification taps, quick actions).
  final bool standalone;

  /// Only show dues due on this specific day (from /dues-day?date=YYYY-MM-DD).
  final DateTime? initialDate;

  /// Auto-open the "new due" form on first build (quick action).
  final bool autoAdd;

  const DuesScreen({super.key, this.standalone = false, this.initialDate, this.autoAdd = false});

  @override
  State<DuesScreen> createState() => _DuesScreenState();
}

class _DuesScreenState extends State<DuesScreen> {
  String _statusFilter = '__unsettled';
  String _directionFilter = '__all';
  DateTime? _dateFilter;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _dateFilter = widget.initialDate;
    if (widget.autoAdd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showDueForm(context);
      });
    }
  }

  int get _activeFilterCount =>
      (_statusFilter != '__unsettled' ? 1 : 0) +
      (_directionFilter != '__all' ? 1 : 0) +
      (_dateFilter != null ? 1 : 0);

  void _clearFilters() => setState(() {
        _statusFilter = '__unsettled';
        _directionFilter = '__all';
        _dateFilter = null;
      });

  Future<void> _openFilters(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
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
      if (_dateFilter != null) {
        final f = _dateFilter!;
        if (d.dueDate.year != f.year || d.dueDate.month != f.month || d.dueDate.day != f.day) {
          return false;
        }
      }
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
      appBar: widget.standalone ? AppBar(title: const Text('Dues')) : null,
      floatingActionButton: canManage
          ? AppFab(
              onPressed: () => showDueForm(context),
              tooltip: 'Add due',
              icon: Icons.add,
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
                Row(
                  children: [
                    Expanded(
                      child: SearchField(
                        hint: 'Search dues…',
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    Gap.sm,
                    Badge(
                      isLabelVisible: _activeFilterCount > 0,
                      label: Text('$_activeFilterCount'),
                      child: IconButton.filledTonal(
                        tooltip: 'Filters',
                        onPressed: () => _openFilters(context),
                        icon: const Icon(Icons.tune),
                      ),
                    ),
                  ],
                ),
                if (_activeFilterCount > 0) ...[
                  Gap.sm,
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (_statusFilter != '__unsettled')
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: RemovableChip('Status: ${_kDueStatusFilters[_statusFilter]}',
                                () => setState(() => _statusFilter = '__unsettled')),
                          ),
                        if (_directionFilter != '__all')
                          RemovableChip('Direction: ${_kDueDirectionFilters[_directionFilter]}',
                              () => setState(() => _directionFilter = '__all')),
                        if (_dateFilter != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: RemovableChip('Due: ${formatDate(_dateFilter!)}',
                                () => setState(() => _dateFilter = null)),
                          ),
                      ],
                    ),
                  ),
                ],
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
                : EntityCardList<Due>(
                    listId: 'dues',
                    rows: filtered,
                    onRowTap: (d) => showDueDetail(context, d),
                    // Swipe right to record a payment, left to send a reminder;
                    // long-press for everything else (was the 3-dot menu).
                    wrapCard: (d, card) {
                      final status = dueStatusFromSettled(d, data.settledOf(d.id));
                      final settleable = status == 'open' || status == 'partial';
                      final canCancel = status != 'settled' && status != 'cancelled';
                      final hasContact = d.contactId != null;

                      void remind() {
                        final remaining = roundMoney(d.amount - data.settledOf(d.id));
                        Share.share(buildDueReminderText(
                          contactName: hasContact
                              ? (data.contactsById[d.contactId]?.name ?? 'there')
                              : 'there',
                          dueTitle: d.title,
                          remaining: remaining,
                          dueDate: d.dueDate,
                          currency: currency,
                          direction: d.direction,
                        ));
                      }

                      final pay = (canTxn && settleable)
                          ? RowAction(
                              icon: Icons.payments_outlined,
                              label: 'Record payment',
                              onTap: () => showDuePayment(context, d))
                          : null;
                      final remindAction = (settleable && hasContact)
                          ? RowAction(
                              icon: Icons.campaign_outlined,
                              label: 'Send reminder',
                              onTap: remind)
                          : null;
                      return RowActions(
                        id: d.id,
                        title: d.title,
                        swipeStart: pay,
                        swipeEnd: remindAction,
                        menu: [
                          if (pay != null) pay,
                          if (remindAction != null) remindAction,
                          if (canViewContacts && hasContact)
                            RowAction(
                                icon: Icons.person_outline,
                                label: 'View contact',
                                onTap: () => context.push('/contacts/${d.contactId}')),
                          if (canViewTxns && hasContact)
                            RowAction(
                                icon: Icons.receipt_long_outlined,
                                label: 'View transactions',
                                onTap: () => context.push('/txns?contact=${d.contactId}')),
                          if (canManage)
                            RowAction(
                                icon: Icons.edit_outlined,
                                label: 'Edit',
                                onTap: () => showDueForm(context, existing: d)),
                          if (canManage && canCancel)
                            RowAction(
                                icon: Icons.block,
                                label: 'Cancel due',
                                onTap: () => _cancelDue(context, d)),
                          if (canManage)
                            RowAction(
                                icon: Icons.delete_outline,
                                label: 'Delete',
                                destructive: true,
                                onTap: () => _confirmDelete(context, d)),
                        ],
                        child: card,
                      );
                    },
                    fields: [
                      CardField<Due>(
                        key: 'title',
                        label: 'Title',
                        role: CardRole.title,
                        locked: true,
                        sortValue: (d) => d.title,
                        text: (d) => d.title,
                      ),
                      // No direction field: the amount's green/red already says
                      // receivable vs payable (Direction stays as a filter).
                      CardField<Due>(
                        key: 'contact',
                        label: 'Contact',
                        icon: Icons.person_outline,
                        defaultVisible: false,
                        sortValue: (d) => d.contactId != null ? data.contactsById[d.contactId]?.name ?? '' : '',
                        text: (d) => d.contactId != null ? data.contactsById[d.contactId]?.name ?? '—' : '—',
                      ),
                      CardField<Due>(
                        key: 'dueDate',
                        label: 'Due date',
                        icon: Icons.event,
                        sortValue: (d) => d.dueDate,
                        text: (d) => formatDate(d.dueDate),
                      ),
                      CardField<Due>(
                        key: 'amount',
                        label: 'Amount',
                        role: CardRole.amount,
                        sortValue: (d) => d.amount,
                        widget: (d) => Text(
                          formatMoney(d.amount, currency),
                          style: TextStyle(
                            color: d.direction == 'receivable' ? AppColors.accent2 : AppColors.danger,
                          ),
                        ),
                      ),
                      CardField<Due>(
                        key: 'settled',
                        label: 'Settled',
                        icon: Icons.check_circle_outline,
                        defaultVisible: false,
                        sortValue: (d) => data.settledOf(d.id),
                        text: (d) => formatMoney(data.settledOf(d.id), currency),
                      ),
                      CardField<Due>(
                        key: 'status',
                        label: 'Status',
                        icon: Icons.flag_outlined,
                        sortValue: (d) => dueStatusFromSettled(d, data.settledOf(d.id)),
                        text: (d) => dueStatusFromSettled(d, data.settledOf(d.id)),
                      ),
                    ],
                  ),
          ),
        ],
      ),
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
    useRootNavigator: true,
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
              await deleteWithUndo(context,
                  actor: Actor.fromUser(user),
                  collection: 'dues',
                  workspaceId: ws,
                  id: due.id,
                  label: 'Due');
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
    useRootNavigator: true,
    isScrollControlled: true,
    // Guarded form: a swipe-down would pop the route without asking, so
    // dragging is off and DiscardGuard supplies the close button.
    showDragHandle: false,
    enableDrag: false,
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
  // Unsaved-edit detection: snapshot on open, compare on close.
  late final String _fp0;
  String _fp() => [_amount.text, '$_accountId'].join('|');

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
    _fp0 = _fp();
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
      // Materialize the transaction FROM the due's stored lines (the due IS
      // the transaction blueprint) — shared with the statement importer.
      final draft = buildDueSettlement(due, amount, data.debtsById, lineIdSeed: lid);
      await Mutations(Actor.fromUser(user)).settleDue(
        ws,
        due.id,
        date: now,
        note: (due.note?.isNotEmpty ?? false) ? due.note : due.title,
        accountId: _accountId!,
        contactId: due.contactId,
        totalAmount: draft.signedTotal,
        financialYear: financialYearOf(now, fyStart),
        lines: draft.lines,
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
    return DiscardGuard(
      title: 'Record payment: ${widget.due.title}',
      isDirty: () => _fp() != _fp0,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final data = context.watch<DataController>();
    final accounts = data.accounts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: kSheetFieldTopPad),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
