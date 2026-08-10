import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import 'due_form.dart';

class DuesScreen extends StatelessWidget {
  const DuesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canManage = ws.can('dues.manage');
    final canTxn = ws.can('transactions.create');

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

    // Default view: unsettled (open + partial).
    final unsettled = data.dues.where((d) {
      final st = dueStatusFromSettled(d, data.settledOf(d.id));
      return st == 'open' || st == 'partial';
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        children: [
          if (receivable > 0 || payable > 0)
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
          if (unsettled.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 40), child: EmptyView(title: 'No unsettled dues'))
          else
            for (final d in unsettled)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(d.title),
                  subtitle: Text('${d.direction == 'receivable' ? 'Receivable' : 'Payable'} · due ${formatDate(d.dueDate)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatMoney(d.amount - data.settledOf(d.id), currency),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (canManage || canTxn) _DueMenu(due: d, canManage: canManage, canTxn: canTxn),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _DueMenu extends StatelessWidget {
  final Due due;
  final bool canManage;
  final bool canTxn;
  const _DueMenu({required this.due, required this.canManage, required this.canTxn});

  @override
  Widget build(BuildContext context) {
    final data = context.read<DataController>();
    final status = dueStatusFromSettled(due, data.settledOf(due.id));
    final settleable = status == 'open' || status == 'partial';
    final canCancel = status != 'settled' && status != 'cancelled';
    return PopupMenuButton<String>(
      onSelected: (v) {
        switch (v) {
          case 'pay':
            _showDuePayment(context, due);
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

Future<void> _showDuePayment(BuildContext context, Due due) {
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
