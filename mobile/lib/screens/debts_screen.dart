import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import '../widgets/discard_guard.dart';
import '../widgets/entity_card_list.dart';
import '../widgets/row_actions.dart';
import '../widgets/undo_delete.dart';
import 'debt_detail.dart';
import 'debt_form.dart';

const _kPurposeLabels = <String, String>{
  'loan': 'Loan',
  'custodial_savings': 'Custodial savings',
  'lending': 'Lending',
  'reimbursable': 'Reimbursable',
  'informal': 'Informal',
  'shared': 'Shared',
};

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  String _search = '';
  String _status = 'outstanding'; // outstanding | settled | all (default outstanding)
  String _direction = 'all'; // all | owe (you owe) | owed (they owe)

  static const _statusLabels = {'outstanding': 'Outstanding', 'settled': 'Settled', 'all': 'All'};
  static const _dirLabels = {'all': 'All', 'owed': 'They owe', 'owe': 'You owe'};

  int get _activeFilterCount =>
      (_status != 'outstanding' ? 1 : 0) + (_direction != 'all' ? 1 : 0);

  // Same filter UX as Transactions/Dues: a bottom sheet with dropdowns, opened
  // from the tonal filter button; active choices surface as removable chips.
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
                    value: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      for (final e in _statusLabels.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => update(() => _status = v ?? 'outstanding'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _direction,
                    decoration: const InputDecoration(labelText: 'Direction'),
                    items: [
                      for (final e in _dirLabels.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => update(() => _direction = v ?? 'all'),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => update(() {
                            _status = 'outstanding';
                            _direction = 'all';
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

  Widget _chip(String label, VoidCallback onClear) => InputChip(
        label: Text(label),
        onDeleted: onClear,
        deleteIcon: const Icon(Icons.close, size: 16),
      );

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canManage = ws.can('debts.manage');
    final canTxn = ws.can('transactions.create');
    final canViewContacts = ws.can('contacts.view');
    final canViewTxns = ws.can('transactions.view');

    final query = _search.trim().toLowerCase();
    final hasDebts = data.debts.any((d) => d.purpose != 'shared');
    final visible = data.debts.where((d) {
      if (d.purpose == 'shared') return false;
      if (_status == 'outstanding' && d.status == 'settled') return false;
      if (_status == 'settled' && d.status != 'settled') return false;
      if (_direction != 'all' && d.direction != _direction) return false;
      if (query.isNotEmpty) {
        final contactName = data.contactsById[d.contactId]?.name ?? '';
        final purposeLabel = _kPurposeLabels[d.purpose] ?? d.purpose;
        final hay = '${d.label ?? ''} $contactName $purposeLabel'.toLowerCase();
        if (!hay.contains(query)) return false;
      }
      return true;
    }).toList();
    var theyOwe = 0.0;
    var youOwe = 0.0;
    for (final d in visible) {
      final o = data.outstandingOf(d.id);
      if (o <= 0.005) continue;
      if (d.direction == 'owed') {
        theyOwe += o;
      } else {
        youOwe += o;
      }
    }
    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton(
              onPressed: () => showDebtForm(context),
              tooltip: 'Add debt',
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          if (theyOwe > 0 || youOwe > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  if (theyOwe > 0)
                    Expanded(child: StatCard(label: 'They owe you', amount: theyOwe, currency: currency, tone: StatTone.success, icon: Icons.arrow_downward)),
                  if (theyOwe > 0 && youOwe > 0) const SizedBox(width: 12),
                  if (youOwe > 0)
                    Expanded(child: StatCard(label: 'You owe', amount: youOwe, currency: currency, tone: StatTone.danger, icon: Icons.arrow_upward)),
                ],
              ),
            ),
          if (hasDebts) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      decoration: const InputDecoration(
                        hintText: 'Search debts…',
                        prefixIcon: Icon(Icons.search, size: 20),
                        isDense: true,
                      ),
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
            ),
            if (_activeFilterCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (_status != 'outstanding')
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _chip('Status: ${_statusLabels[_status]}',
                              () => setState(() => _status = 'outstanding')),
                        ),
                      if (_direction != 'all')
                        _chip('Direction: ${_dirLabels[_direction]}',
                            () => setState(() => _direction = 'all')),
                    ],
                  ),
                ),
              ),
          ],
          Expanded(
            child: visible.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: EmptyView(
                      title: (query.isNotEmpty || _activeFilterCount > 0)
                          ? 'No debts match the filters'
                          : 'No debts yet',
                      icon: (query.isNotEmpty || _activeFilterCount > 0)
                          ? Icons.filter_alt_off
                          : Icons.credit_card_outlined,
                    ),
                  )
                : EntityCardList<Debt>(
                    listId: 'debts',
                    rows: visible,
                    onRowTap: (d) => showDebtDetail(context, d),
                    // Swipe right to record a receipt/repayment; long-press for
                    // the full action sheet (was the 3-dot menu).
                    wrapCard: (d, card) {
                      final outstanding = data.outstandingOf(d.id);
                      final settleable = d.status == 'open' && outstanding > 0;
                      final hasContact = d.contactId.isNotEmpty;
                      final settle = (canTxn && settleable)
                          ? RowAction(
                              icon: Icons.payments_outlined,
                              label: d.direction == 'owed' ? 'Record receipt' : 'Record repayment',
                              onTap: () => showDebtPayment(context, d))
                          : null;
                      return RowActions(
                        id: d.id,
                        title: d.label ?? data.contactsById[d.contactId]?.name ?? 'Debt',
                        swipeStart: settle,
                        menu: [
                          if (settle != null) settle,
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
                                onTap: () => showDebtForm(context, existing: d)),
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
                      CardField<Debt>(
                        key: 'label',
                        label: 'Label',
                        role: CardRole.title,
                        locked: true,
                        sortValue: (d) => d.label ?? data.contactsById[d.contactId]?.name ?? 'Debt',
                        text: (d) => d.label ?? data.contactsById[d.contactId]?.name ?? 'Debt',
                      ),
                      CardField<Debt>(
                        key: 'contact',
                        label: 'Contact',
                        icon: Icons.person_outline,
                        sortValue: (d) => data.contactsById[d.contactId]?.name ?? '',
                        text: (d) => data.contactsById[d.contactId]?.name ?? '—',
                      ),
                      CardField<Debt>(
                        key: 'direction',
                        label: 'Direction',
                        icon: Icons.swap_vert,
                        defaultVisible: false,
                        sortValue: (d) => d.direction,
                        text: (d) => d.direction == 'owed' ? 'They owe you' : 'You owe',
                      ),
                      CardField<Debt>(
                        key: 'purpose',
                        label: 'Purpose',
                        icon: Icons.sell_outlined,
                        defaultVisible: false,
                        sortValue: (d) => _kPurposeLabels[d.purpose] ?? d.purpose,
                        text: (d) => _kPurposeLabels[d.purpose] ?? d.purpose,
                      ),
                      CardField<Debt>(
                        key: 'status',
                        label: 'Status',
                        icon: Icons.flag_outlined,
                        sortValue: (d) => d.status,
                        text: (d) => d.status,
                      ),
                      CardField<Debt>(
                        key: 'outstanding',
                        label: 'Outstanding',
                        role: CardRole.amount,
                        sortValue: (d) => data.outstandingOf(d.id),
                        widget: (d) => Text(
                          formatMoney(data.outstandingOf(d.id), currency),
                          style: TextStyle(
                            color: d.direction == 'owed' ? AppColors.accent2 : AppColors.danger,
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
}

void _confirmDelete(BuildContext context, Debt debt) {
  final ws = context.read<WorkspaceController>().activeWorkspaceId;
  final user = context.read<AuthController>().user;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${debt.label ?? 'debt'}"?'),
      content: const Text('Linked transactions keep their reference but this debt will no longer be tracked.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            if (ws == null || user == null) return;
            try {
              await deleteWithUndo(context,
                  actor: Actor.fromUser(user),
                  collection: 'debts',
                  workspaceId: ws,
                  id: debt.id,
                  label: 'Debt');
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

Future<void> showDebtPayment(BuildContext context, Debt debt) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Guarded form: a swipe-down would pop the route without asking, so
    // dragging is off and DiscardGuard supplies the close button.
    showDragHandle: false,
    enableDrag: false,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _DebtPaymentSheet(debt: debt),
    ),
  );
}

class _DebtPaymentSheet extends StatefulWidget {
  final Debt debt;
  const _DebtPaymentSheet({required this.debt});
  @override
  State<_DebtPaymentSheet> createState() => _DebtPaymentSheetState();
}

class _DebtPaymentSheetState extends State<_DebtPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  String? _accountId;
  bool _busy = false;

  // Unsaved-edit detection: snapshot on open, compare on close.
  late final String _fp0;
  String _fp() => [_amount.text, '$_accountId'].join('|');

  @override
  void initState() {
    super.initState();
    final data = context.read<DataController>();
    final outstanding = data.outstandingOf(widget.debt.id);
    _amount = TextEditingController(text: (outstanding > 0 ? outstanding : 0).toString());
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

    final debt = widget.debt;
    final now = DateTime.now();
    final lid = now.microsecondsSinceEpoch;
    final m = Mutations(Actor.fromUser(user));
    setState(() => _busy = true);
    try {
      await m.createTransaction(
        ws,
        date: now,
        note: null,
        accountId: _accountId!,
        contactId: debt.contactId,
        totalAmount: roundMoney(debt.direction == 'owe' ? -amount : amount),
        financialYear: financialYearOf(now, fyStart),
        lines: [
          {'lineId': 'rep_$lid', 'type': 'repayment', 'amount': amount, 'debtId': debt.id},
        ],
      );
      if (data.outstandingOf(debt.id) - amount <= 0.005) {
        await m.updateDebt(ws, debt.id, {'status': 'settled'});
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Repayment recorded')));
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
      title: widget.debt.direction == 'owed' ? 'Record receipt' : 'Record repayment',
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
