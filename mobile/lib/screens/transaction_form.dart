import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';

/// Add-transaction sheet. Single-line entry covering the common types
/// (expense / income / transfer / borrow / lend / repayment). Multi-line splits
/// come from the web engine; this native form builds the equivalent line(s).
Future<void> showTransactionForm(BuildContext context, {Txn? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Use the sheet's own context for MediaQuery — the caller's context may be
    // unmounted (this form is opened right after the detail sheet pops on Edit),
    // and reading MediaQuery off a defunct context blanks the sheet.
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _TransactionForm(existing: existing),
    ),
  );
}

const _kTypes = <String, String>{
  'expense': 'Expense',
  'income': 'Income',
  'transfer': 'Transfer',
  'borrow': 'Borrow',
  'lend': 'Lend',
  'repayment': 'Repayment',
};

class _TransactionForm extends StatefulWidget {
  final Txn? existing;
  const _TransactionForm({this.existing});
  @override
  State<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<_TransactionForm> {
  final _formKey = GlobalKey<FormState>();
  String _type = 'expense';
  DateTime _date = DateTime.now();
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  String? _contactId;
  String? _debtId;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  bool get _isDebtType => _type == 'borrow' || _type == 'lend' || _type == 'repayment';
  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    // Prefill for editing a single-line transaction. Multi-line splits come from
    // the web engine and are edited there, so only single-line txns are prefilled.
    final txn = widget.existing;
    if (txn != null && txn.lines.length == 1) {
      final line = txn.lines.first;
      switch (line.type) {
        case 'transfer_out':
        case 'transfer_in':
          _type = 'transfer';
          break;
        case 'income':
          _type = 'income';
          break;
        case 'expense':
          _type = 'expense';
          break;
        case 'borrow':
        case 'lend':
        case 'repayment':
          _type = line.type;
          break;
        default:
          _type = 'expense';
      }
      _accountId = txn.accountId;
      _date = txn.date;
      _amount.text = line.amount.toString();
      _categoryId = line.categoryId;
      _contactId = txn.contactId;
      _debtId = line.debtId;
      // For a transfer the destination lives on the transfer_in line.
      for (final l in txn.lines) {
        if (l.type == 'transfer_in' && l.toAccountId != null) _toAccountId = l.toAccountId;
      }
      _note.text = txn.note ?? '';
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final wsC = context.read<WorkspaceController>();
    final ws = wsC.activeWorkspaceId;
    final fyStart = wsC.activeWorkspace?.fyStartMonth ?? 4;
    final user = context.read<AuthController>().user;
    final data = context.read<DataController>();
    if (ws == null || user == null || _accountId == null) return;

    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) return;

    final lid = DateTime.now().microsecondsSinceEpoch;
    final lines = <Map<String, dynamic>>[];
    double total;
    String? contactId = _contactId;

    switch (_type) {
      case 'expense':
        lines.add({'lineId': 'l$lid', 'type': 'expense', 'amount': amount, 'categoryId': _categoryId});
        total = -amount;
        break;
      case 'income':
        lines.add({'lineId': 'l$lid', 'type': 'income', 'amount': amount, 'categoryId': _categoryId});
        total = amount;
        break;
      case 'transfer':
        lines.add({'lineId': 'l${lid}a', 'type': 'transfer_out', 'amount': amount});
        lines.add({'lineId': 'l${lid}b', 'type': 'transfer_in', 'amount': amount, 'toAccountId': _toAccountId});
        total = -amount;
        break;
      case 'borrow':
      case 'lend':
      case 'repayment':
        final debt = data.debtsById[_debtId];
        contactId = debt?.contactId;
        lines.add({'lineId': 'l$lid', 'type': _type, 'amount': amount, 'debtId': _debtId});
        if (_type == 'borrow') {
          total = amount;
        } else if (_type == 'lend') {
          total = -amount;
        } else {
          total = (debt?.direction == 'owe' ? -1 : 1) * amount;
        }
        break;
      default:
        return;
    }

    setState(() => _busy = true);
    try {
      final m = Mutations(Actor.fromUser(user));
      final note = _note.text.trim().isEmpty ? null : _note.text.trim();
      if (widget.existing != null) {
        await m.updateTransaction(
          ws,
          widget.existing!.id,
          date: _date,
          note: note,
          accountId: _accountId!,
          contactId: contactId,
          totalAmount: roundMoney(total),
          financialYear: financialYearOf(_date, fyStart),
          lines: lines,
        );
      } else {
        await m.createTransaction(
          ws,
          date: _date,
          note: note,
          accountId: _accountId!,
          contactId: contactId,
          totalAmount: roundMoney(total),
          financialYear: financialYearOf(_date, fyStart),
          lines: lines,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isEditing ? 'Transaction updated' : 'Transaction added')));
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
    final expenseCats = data.categories.where((c) => c.kind == 'expense').toList();
    final incomeCats = data.categories.where((c) => c.kind == 'income').toList();
    final cats = _type == 'income' ? incomeCats : expenseCats;
    final debts = data.debts.where((d) => d.purpose != 'shared').toList();
    final contacts = data.contacts.where((c) => c.connectionUid == null).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isEditing ? 'Edit transaction' : 'New transaction',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final e in _kTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() {
                  _type = v ?? 'expense';
                  _categoryId = null;
                  _debtId = null;
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => (double.tryParse(v?.trim() ?? '') ?? 0) <= 0 ? 'Enter an amount' : null,
              ),
              const SizedBox(height: 12),
              // Date
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date'),
                  child: Text(formatDate(_date)),
                ),
              ),
              const SizedBox(height: 12),
              _accountDropdown('Account', _accountId, accounts, (v) => setState(() => _accountId = v)),
              if (_type == 'transfer') ...[
                const SizedBox(height: 12),
                _accountDropdown('To account', _toAccountId,
                    accounts.where((a) => a.id != _accountId).toList(), (v) => setState(() => _toAccountId = v),
                    validator: (v) => v == null ? 'Pick a destination' : null),
              ],
              if (_type == 'expense' || _type == 'income') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: cats.any((c) => c.id == _categoryId) ? _categoryId : null,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: contacts.any((c) => c.id == _contactId) ? _contactId : null,
                  decoration: const InputDecoration(labelText: 'Contact (optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    for (final c in contacts) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _contactId = v),
                ),
              ],
              if (_isDebtType) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: debts.any((d) => d.id == _debtId) ? _debtId : null,
                  decoration: const InputDecoration(labelText: 'Debt'),
                  items: [
                    for (final d in debts)
                      DropdownMenuItem(
                        value: d.id,
                        child: Text('${d.label ?? data.contactsById[d.contactId]?.name ?? 'Debt'}'
                            ' · ${d.direction == 'owe' ? 'you owe' : 'they owe'}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _debtId = v),
                  validator: (v) => v == null ? 'Pick a debt' : null,
                ),
                if (debts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('No debts yet — create one under Debts first.',
                        style: TextStyle(fontSize: 12, color: Colors.orange)),
                  ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
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

  Widget _accountDropdown(
    String label,
    String? value,
    List<Account> accounts,
    ValueChanged<String?> onChanged, {
    String? Function(String?)? validator,
  }) {
    // Guard: a prefilled id that no longer exists in the list (deleted account)
    // would trip DropdownButtonFormField's "exactly one item" assertion and blank
    // the whole form — fall back to null instead.
    final safe = accounts.any((a) => a.id == value) ? value : null;
    return DropdownButtonFormField<String>(
      value: safe,
      decoration: InputDecoration(labelText: label),
      items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
      onChanged: onChanged,
      validator: validator ?? (v) => v == null ? 'Pick an account' : null,
    );
  }
}
