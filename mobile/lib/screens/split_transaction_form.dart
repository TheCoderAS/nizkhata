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
Future<void> showSplitTransactionForm(BuildContext context, {Txn? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Own context for MediaQuery — the caller's may be unmounted when this is
    // opened right after the detail sheet pops on Edit (would blank the sheet).
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _SplitTransactionForm(existing: existing),
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

/// Line types that may carry a tax block (mirrors CAN_TAX in the web form).
bool _canTax(String type) => type == 'income' || type == 'interest_income';

/// Render a stored amount into an editable text field (drops a trailing `.0`).
String _amountText(double v) {
  if (v == 0) return '';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// Tax head keys + labels, in display order (mirrors src/lib/taxHeads.ts).
const _kTaxHeads = <String, String>{
  'salary': 'Salary',
  'bonus': 'Bonus',
  'overtime': 'Overtime',
  'reimbursement': 'Reimbursement',
  'perquisite': 'Perquisite',
  'commission': 'Commission',
  'professional_fees': 'Professional fees',
  'rent': 'Rent',
  'interest': 'Interest',
  'dividend': 'Dividend',
  'capital_gains': 'Capital gains',
  'business': 'Business / profession',
  'other': 'Other',
  'exempt': 'Exempt',
};

class _LineRow {
  String type;
  final TextEditingController amount = TextEditingController();
  String? categoryId;
  String? toAccountId;
  String? debtId;
  // Preserved line id when editing an existing transaction (null for new lines).
  String? lineId;
  // Per-line tax entry (only meaningful for income / interest_income lines).
  bool taxable = false;
  String taxHead = 'other';
  final TextEditingController tds = TextEditingController();
  bool taxInclusive = false;
  _LineRow({this.type = 'expense', this.lineId});

  factory _LineRow.fromLine(TxnLine l) {
    final row = _LineRow(type: l.type, lineId: l.lineId);
    row.amount.text = _amountText(l.amount);
    row.categoryId = l.categoryId;
    row.toAccountId = l.toAccountId;
    row.debtId = l.debtId;
    final tax = l.tax;
    if (tax != null) {
      row.taxable = tax['taxable'] == true;
      final h = tax['head'];
      if (h is String && h.isNotEmpty) row.taxHead = h;
      final tdsAmt = tax['tdsAmount'];
      if (tdsAmt is num && tdsAmt != 0) row.tds.text = _amountText(tdsAmt.toDouble());
      row.taxInclusive = tax['taxInclusive'] == true;
    }
    return row;
  }
}

class _SplitTransactionForm extends StatefulWidget {
  final Txn? existing;
  const _SplitTransactionForm({this.existing});
  @override
  State<_SplitTransactionForm> createState() => _SplitTransactionFormState();
}

class _SplitTransactionFormState extends State<_SplitTransactionForm> {
  DateTime _date = DateTime.now();
  String? _accountId;
  String? _contactId;
  final _note = TextEditingController();
  late final List<_LineRow> _lines;
  bool _busy = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final txn = widget.existing;
    if (txn != null) {
      _date = txn.date;
      _accountId = txn.accountId;
      _contactId = txn.contactId;
      _note.text = txn.note ?? '';
      _lines = [for (final l in txn.lines) _LineRow.fromLine(l)];
      if (_lines.isEmpty) _lines.add(_LineRow(type: 'expense'));
    } else {
      _lines = [_LineRow(type: 'expense'), _LineRow(type: 'income')];
    }
  }

  @override
  void dispose() {
    _note.dispose();
    for (final l in _lines) {
      l.amount.dispose();
      l.tds.dispose();
    }
    super.dispose();
  }

  void _addLine() => setState(() => _lines.add(_LineRow()));

  void _removeLine(int i) {
    if (_lines.length <= 1) return;
    setState(() {
      final removed = _lines.removeAt(i);
      removed.amount.dispose();
      removed.tds.dispose();
    });
  }

  double _amountOf(_LineRow r) => double.tryParse(r.amount.text.trim()) ?? 0;

  /// Build the {taxable, head, tdsAmount, taxInclusive} map for a line, or null
  /// when the line can't/doesn't carry tax. Mirrors the web TaxBlock output.
  Map<String, dynamic>? _taxOf(_LineRow r) {
    if (!_canTax(r.type) || !r.taxable) return null;
    return {
      'taxable': true,
      'head': r.taxHead,
      'tdsAmount': double.tryParse(r.tds.text.trim()) ?? 0,
      'taxInclusive': r.taxInclusive,
    };
  }

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
        tax: _taxOf(r),
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
      final tax = _taxOf(r);
      lines.add({
        'lineId': r.lineId ?? 'l${i}_$micros',
        'type': r.type,
        'amount': _amountOf(r),
        if (_needsCategory(r.type)) 'categoryId': r.categoryId,
        if (_needsToAccount(r.type)) 'toAccountId': r.toAccountId,
        if (_needsDebt(r.type)) 'debtId': r.debtId,
        if (tax != null) 'tax': tax,
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
      if (widget.existing != null) {
        await m.updateTransaction(
          ws,
          widget.existing!.id,
          date: _date,
          note: note,
          accountId: _accountId!,
          contactId: contactId,
          totalAmount: total,
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
          totalAmount: total,
          financialYear: financialYearOf(_date, fyStart),
          lines: lines,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isEditing ? 'Transaction updated' : 'Transaction added')));
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
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEditing ? 'Edit split transaction' : 'Split transaction',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _sectionLabel('Details'),
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
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              // Guard stale ids (deleted account) → null, else the form blanks.
              value: accounts.any((a) => a.id == _accountId) ? _accountId : null,
              decoration: const InputDecoration(labelText: 'Account'),
              items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: contacts.any((c) => c.id == _contactId) ? _contactId : null,
              decoration: const InputDecoration(labelText: 'Contact (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (final c in contacts) DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _contactId = v),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Lines'.toUpperCase(), style: _sectionLabelStyle),
                TextButton.icon(
                  onPressed: _addLine,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add line'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < _lines.length; i++) _lineCard(i, data, accounts, debts),
            const SizedBox(height: 14),
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
      ),
    );
  }

  /// Muted, spaced-out label for grouping a set of related fields.
  TextStyle? get _sectionLabelStyle => Theme.of(context).textTheme.titleSmall?.copyWith(
        fontSize: 12,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(), style: _sectionLabelStyle),
      );

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
                    value: _kLineTypes.containsKey(r.type) ? r.type : null,
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
                value: cats.any((c) => c.id == r.categoryId) ? r.categoryId : null,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() => r.categoryId = v),
              ),
            ],
            if (_needsToAccount(r.type)) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: accounts.any((a) => a.id == r.toAccountId && a.id != _accountId) ? r.toAccountId : null,
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
                value: debts.any((d) => d.id == r.debtId) ? r.debtId : null,
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
            if (_canTax(r.type)) ...[
              const SizedBox(height: 8),
              _taxBlock(i),
            ],
          ],
        ),
      ),
    );
  }

  /// Compact per-line tax entry for income / interest_income lines. Mirrors the
  /// web TaxBlock: a "Tax info" toggle that reveals head / TDS / tax-inclusive.
  Widget _taxBlock(int i) {
    final r = _lines[i];
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: r.taxable,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => setState(() => r.taxable = v ?? false),
              ),
              const Text('Tax info', style: TextStyle(fontSize: 13)),
            ],
          ),
          if (r.taxable) ...[
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: _kTaxHeads.containsKey(r.taxHead) ? r.taxHead : null,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Head'),
              items: [
                for (final e in _kTaxHeads.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => r.taxHead = v ?? 'other'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: r.tds,
              decoration: const InputDecoration(labelText: 'TDS', prefixText: '₹ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Checkbox(
                  value: r.taxInclusive,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => setState(() => r.taxInclusive = v ?? false),
                ),
                const Expanded(
                  child: Text('Amount is tax-inclusive', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
