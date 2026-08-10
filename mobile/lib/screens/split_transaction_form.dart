import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';

/// Multi-line "split" transaction sheet. Ports the web engine's split editor:
/// a header (date / account / contact / note) plus a dynamic list of typed
/// lines. The signed header total and validation are derived from the same
/// primitives as the web app (computeTotal + the txn.ts rules).
Future<void> showSplitTransactionForm(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: const _SplitTransactionForm(),
    ),
  );
}

/// All eleven line types, labelled exactly as the web app (lineTypes.ts).
const _kLineTypes = <String, String>{
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
  'tax': 'Tax / GST',
};

bool _needsCategory(String type) =>
    type == 'income' ||
    type == 'expense' ||
    type == 'fee' ||
    type == 'tax' ||
    type == 'interest_income' ||
    type == 'interest_expense';

bool _isIncomeCategory(String type) => type == 'income' || type == 'interest_income';

bool _needsToAccount(String type) => type == 'transfer_in';

bool _needsDebt(String type) => type == 'borrow' || type == 'lend' || type == 'repayment';

class _LineRow {
  String type;
  final TextEditingController amount = TextEditingController();
  String? categoryId;
  String? toAccountId;
  String? debtId;
  _LineRow({this.type = 'expense'});
}

class _SplitTransactionForm extends StatefulWidget {
  const _SplitTransactionForm();
  @override
  State<_SplitTransactionForm> createState() => _SplitTransactionFormState();
}

class _SplitTransactionFormState extends State<_SplitTransactionForm> {
  DateTime _date = DateTime.now();
  String? _accountId;
  String? _contactId;
  final _note = TextEditingController();
  final List<_LineRow> _lines = [_LineRow(type: 'expense'), _LineRow(type: 'income')];
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    for (final l in _lines) {
      l.amount.dispose();
    }
    super.dispose();
  }

  void _addLine() => setState(() => _lines.add(_LineRow()));

  void _removeLine(int i) {
    if (_lines.length <= 1) return;
    setState(() {
      _lines.removeAt(i).amount.dispose();
    });
  }

  double _amountOf(_LineRow r) => double.tryParse(r.amount.text.trim()) ?? 0;

  /// Build the engine's TxnLine objects from the current rows so we can call
  /// computeTotal / the validation rules against the same primitives as the web.
  List<TxnLine> _txnLines() {
    final out = <TxnLine>[];
    for (var i = 0; i < _lines.length; i++) {
      final r = _lines[i];
      out.add(TxnLine(
        lineId: 'l$i',
        type: r.type,
        amount: _amountOf(r),
        categoryId: _needsCategory(r.type) ? r.categoryId : null,
        toAccountId: _needsToAccount(r.type) ? r.toAccountId : null,
        debtId: _needsDebt(r.type) ? r.debtId : null,
      ));
    }
    return out;
  }

  /// Live validation mirroring src/lib/txn.ts (validateLine + validateTransaction).
  List<String> _errors() {
    final errs = <String>[];
    if (_accountId == null) errs.add('Pick an account.');
    final lines = _txnLines();
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final n = i + 1;
      if (!(l.amount > 0)) errs.add('Line $n: amount must be greater than 0.');
      if (_needsDebt(l.type) && l.debtId == null) errs.add('Line $n: a ${_kLineTypes[l.type]!.toLowerCase()} line must link a debt.');
      if (l.type == 'transfer_in') {
        if (l.toAccountId == null) {
          errs.add('Line $n: a transfer-in line needs a destination account.');
        } else if (l.toAccountId == _accountId) {
          errs.add('Line $n: transfer destination must differ from the source account.');
        }
      }
    }
    final linksDebt = lines.any((l) => _needsDebt(l.type));
    if (linksDebt && _contactId == null) {
      errs.add('Borrow / lend / repayment lines require a contact on the transaction.');
    }
    final outSum = lines.where((l) => l.type == 'transfer_out').fold<double>(0, (s, l) => s + l.amount);
    final inSum = lines.where((l) => l.type == 'transfer_in').fold<double>(0, (s, l) => s + l.amount);
    if ((outSum - inSum).abs() > 0.005) {
      errs.add('Transfer lines must balance: total transfer-out must equal total transfer-in.');
    }
    return errs;
  }

  Future<void> _save() async {
    final wsC = context.read<WorkspaceController>();
    final ws = wsC.activeWorkspaceId;
    final fyStart = wsC.activeWorkspace?.fyStartMonth ?? 4;
    final user = context.read<AuthController>().user;
    final data = context.read<DataController>();
    if (ws == null || user == null || _accountId == null) return;
    if (_errors().isNotEmpty) return;

    final micros = DateTime.now().microsecondsSinceEpoch;
    final lines = <Map<String, dynamic>>[];
    for (var i = 0; i < _lines.length; i++) {
      final r = _lines[i];
      lines.add({
        'lineId': 'l${i}_$micros',
        'type': r.type,
        'amount': _amountOf(r),
        if (_needsCategory(r.type)) 'categoryId': r.categoryId,
        if (_needsToAccount(r.type)) 'toAccountId': r.toAccountId,
        if (_needsDebt(r.type)) 'debtId': r.debtId,
      });
    }

    // Header contact wins; otherwise fall back to a debt line's contact.
    String? contactId = _contactId;
    if (contactId == null) {
      for (final r in _lines) {
        if (_needsDebt(r.type) && r.debtId != null) {
          contactId = data.debtsById[r.debtId]?.contactId;
          break;
        }
      }
    }

    final total = computeTotal(_txnLines(), data.debtsById);

    setState(() => _busy = true);
    try {
      final m = Mutations(Actor.fromUser(user));
      final note = _note.text.trim().isEmpty ? null : _note.text.trim();
      await m.createTransaction(
        ws,
        date: _date,
        note: note,
        accountId: _accountId!,
        contactId: contactId,
        totalAmount: total,
        financialYear: financialYearOf(_date, fyStart),
        lines: lines,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction added')));
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
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final accounts = data.accounts;
    final debts = data.debts.where((d) => d.purpose != 'shared').toList();
    final contacts = data.contacts.where((c) => c.connectionUid == null).toList();

    final total = computeTotal(_txnLines(), data.debtsById);
    final errors = _errors();
    final canSave = !_busy && accounts.isNotEmpty && errors.isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Split transaction', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
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
            DropdownButtonFormField<String>(
              value: _accountId,
              decoration: const InputDecoration(labelText: 'Account'),
              items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _contactId,
              decoration: const InputDecoration(labelText: 'Contact (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (final c in contacts) DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _contactId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Lines', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: _addLine,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add line'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < _lines.length; i++) _lineCard(i, data, accounts, debts),
            const SizedBox(height: 12),
            // Live computed total.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    formatMoney(total, currency),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: total < 0 ? AppColors.danger : AppColors.accent2,
                    ),
                  ),
                ],
              ),
            ),
            if (accounts.isNotEmpty && errors.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final e in errors)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(e, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canSave ? _save : null,
                child: _busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(accounts.isEmpty ? 'Add an account first' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineCard(int i, DataController data, List<Account> accounts, List<Debt> debts) {
    final r = _lines[i];
    final cats = data.categories
        .where((c) => c.kind == (_isIncomeCategory(r.type) ? 'income' : 'expense'))
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: r.type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      for (final e in _kLineTypes.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() {
                      r.type = v ?? 'expense';
                      r.categoryId = null;
                      r.toAccountId = null;
                      r.debtId = null;
                    }),
                  ),
                ),
                IconButton(
                  onPressed: _lines.length > 1 ? () => _removeLine(i) : null,
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove line',
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: r.amount,
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            if (_needsCategory(r.type)) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: r.categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() => r.categoryId = v),
              ),
            ],
            if (_needsToAccount(r.type)) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: r.toAccountId,
                decoration: const InputDecoration(labelText: 'To account'),
                items: [
                  for (final a in accounts.where((a) => a.id != _accountId))
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => r.toAccountId = v),
              ),
            ],
            if (_needsDebt(r.type)) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: r.debtId,
                decoration: const InputDecoration(labelText: 'Debt'),
                items: [
                  for (final d in debts)
                    DropdownMenuItem(
                      value: d.id,
                      child: Text('${d.label ?? data.contactsById[d.contactId]?.name ?? 'Debt'}'
                          ' · ${d.direction == 'owe' ? 'you owe' : 'they owe'}'),
                    ),
                ],
                onChanged: (v) => setState(() => r.debtId = v),
              ),
              if (debts.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('No debts yet — create one under Debts first.',
                      style: TextStyle(fontSize: 12, color: Colors.orange)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
