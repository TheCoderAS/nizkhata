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

class DebtsScreen extends StatelessWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canManage = ws.can('debts.manage');
    final canTxn = ws.can('transactions.create');
    final canViewContacts = ws.can('contacts.view');
    final canViewTxns = ws.can('transactions.view');

    final visible = data.debts.where((d) => d.purpose != 'shared').toList();
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
          ? FloatingActionButton.extended(
              onPressed: () => showDebtForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Debt'),
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
          Expanded(
            child: visible.isEmpty
                ? const Padding(padding: EdgeInsets.only(top: 40), child: EmptyView(title: 'No debts yet'))
                : DataTableView<Debt>(
                    tableId: 'debts',
                    rows: visible,
                    onRowTap: (d) => showDebtDetail(context, d),
                    trailing: (d) => (canManage || canTxn || canViewContacts || canViewTxns)
                        ? _DebtMenu(
                            debt: d,
                            canManage: canManage,
                            canTxn: canTxn,
                            canViewContacts: canViewContacts,
                            canViewTxns: canViewTxns,
                          )
                        : const SizedBox.shrink(),
                    columns: [
                      DataColumn2<Debt>(
                        key: 'label',
                        label: 'Label',
                        locked: true,
                        defaultWidth: 170,
                        sortValue: (d) => d.label ?? data.contactsById[d.contactId]?.name ?? 'Debt',
                        cell: (d) => Text(d.label ?? data.contactsById[d.contactId]?.name ?? 'Debt',
                            overflow: TextOverflow.ellipsis),
                      ),
                      DataColumn2<Debt>(
                        key: 'contact',
                        label: 'Contact',
                        defaultWidth: 150,
                        sortValue: (d) => data.contactsById[d.contactId]?.name ?? '',
                        cell: (d) => Text(data.contactsById[d.contactId]?.name ?? '—',
                            overflow: TextOverflow.ellipsis),
                      ),
                      DataColumn2<Debt>(
                        key: 'direction',
                        label: 'Direction',
                        defaultVisible: false,
                        defaultWidth: 130,
                        sortValue: (d) => d.direction,
                        cell: (d) => Text(d.direction == 'owed' ? 'They owe you' : 'You owe',
                            overflow: TextOverflow.ellipsis),
                      ),
                      DataColumn2<Debt>(
                        key: 'purpose',
                        label: 'Purpose',
                        defaultVisible: false,
                        defaultWidth: 140,
                        sortValue: (d) => _kPurposeLabels[d.purpose] ?? d.purpose,
                        cell: (d) => Text(_kPurposeLabels[d.purpose] ?? d.purpose,
                            overflow: TextOverflow.ellipsis),
                      ),
                      DataColumn2<Debt>(
                        key: 'status',
                        label: 'Status',
                        defaultWidth: 100,
                        sortValue: (d) => d.status,
                        cell: (d) => Text(d.status),
                      ),
                      DataColumn2<Debt>(
                        key: 'outstanding',
                        label: 'Outstanding',
                        numeric: true,
                        defaultWidth: 130,
                        sortValue: (d) => data.outstandingOf(d.id),
                        cell: (d) => Text(formatMoney(data.outstandingOf(d.id), currency),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DebtMenu extends StatelessWidget {
  final Debt debt;
  final bool canManage;
  final bool canTxn;
  final bool canViewContacts;
  final bool canViewTxns;
  const _DebtMenu({
    required this.debt,
    required this.canManage,
    required this.canTxn,
    required this.canViewContacts,
    required this.canViewTxns,
  });

  @override
  Widget build(BuildContext context) {
    final data = context.read<DataController>();
    final outstanding = data.outstandingOf(debt.id);
    final settleable = debt.status == 'open' && outstanding > 0;
    final settleLabel = debt.direction == 'owed' ? 'Record receipt' : 'Record repayment';
    final hasContact = debt.contactId.isNotEmpty;
    return PopupMenuButton<String>(
      onSelected: (v) {
        switch (v) {
          case 'settle':
            _showDebtPayment(context, debt);
            break;
          case 'contact':
            if (hasContact) context.push('/contacts/${debt.contactId}');
            break;
          case 'edit':
            showDebtForm(context, existing: debt);
            break;
          case 'delete':
            _confirmDelete(context, debt);
            break;
        }
      },
      itemBuilder: (_) => [
        if (canTxn && settleable) PopupMenuItem(value: 'settle', child: Text(settleLabel)),
        if (canViewContacts && hasContact) const PopupMenuItem(value: 'contact', child: Text('View contact')),
        if (canManage) const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (canManage) const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
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
              await Mutations(Actor.fromUser(user)).deleteDebt(ws, debt.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debt deleted')));
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

Future<void> _showDebtPayment(BuildContext context, Debt debt) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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

  @override
  void initState() {
    super.initState();
    final data = context.read<DataController>();
    final outstanding = data.outstandingOf(widget.debt.id);
    _amount = TextEditingController(text: (outstanding > 0 ? outstanding : 0).toString());
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
    final data = context.watch<DataController>();
    final accounts = data.accounts;
    final title = widget.debt.direction == 'owed' ? 'Record receipt' : 'Record repayment';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
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
