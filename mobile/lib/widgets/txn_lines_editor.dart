// Shared multi-line transaction editor — the line cards (type / amount /
// category / to-account / debt / tax info) used by BOTH the transaction form
// and the due form, so a due is authored with exactly the same power as a
// transaction. State lives in [LineDraft]s owned by the parent form; every
// mutation calls [onChanged] so the parent rebuilds (and recomputes totals).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/data_controller.dart';

/// All eleven line types, labelled exactly as the web app (lineTypes.ts).
const kLineTypes = <String, String>{
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

bool needsCategory(String type) =>
    type == 'income' ||
    type == 'expense' ||
    type == 'fee' ||
    type == 'tax' ||
    type == 'interest_income' ||
    type == 'interest_expense';

bool isIncomeCategory(String type) => type == 'income' || type == 'interest_income';

bool needsToAccount(String type) => type == 'transfer_in';

bool needsDebt(String type) => type == 'borrow' || type == 'lend' || type == 'repayment';

/// Line types that may carry a tax block (mirrors CAN_TAX in the web form).
bool canTax(String type) => type == 'income' || type == 'interest_income';

/// Render a stored amount into an editable text field (drops a trailing `.0`).
String amountText(double v) {
  if (v == 0) return '';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// Tax head keys + labels, in display order (mirrors src/lib/taxHeads.ts).
const kTaxHeads = <String, String>{
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

/// Mutable draft of one transaction line while it's being edited.
class LineDraft {
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
  LineDraft({this.type = 'expense', this.lineId});

  factory LineDraft.fromLine(TxnLine l) {
    final row = LineDraft(type: l.type, lineId: l.lineId);
    row.amount.text = amountText(l.amount);
    row.categoryId = l.categoryId;
    row.toAccountId = l.toAccountId;
    row.debtId = l.debtId;
    final tax = l.tax;
    if (tax != null) {
      row.taxable = tax['taxable'] == true;
      final h = tax['head'];
      if (h is String && h.isNotEmpty) row.taxHead = h;
      final tdsAmt = tax['tdsAmount'];
      if (tdsAmt is num && tdsAmt != 0) row.tds.text = amountText(tdsAmt.toDouble());
      row.taxInclusive = tax['taxInclusive'] == true;
    }
    return row;
  }

  double get amountValue => double.tryParse(amount.text.trim()) ?? 0;

  /// {taxable, head, tdsAmount, taxInclusive} for the line, or null when the
  /// line can't/doesn't carry tax. Mirrors the web TaxBlock output.
  Map<String, dynamic>? taxMap() {
    if (!canTax(type) || !taxable) return null;
    return {
      'taxable': true,
      'head': taxHead,
      'tdsAmount': double.tryParse(tds.text.trim()) ?? 0,
      'taxInclusive': taxInclusive,
    };
  }

  /// Engine TxnLine (for computeTotal / validation) with a positional id.
  TxnLine toTxnLine(int i) => TxnLine(
        lineId: 'l$i',
        type: type,
        amount: amountValue,
        categoryId: needsCategory(type) ? categoryId : null,
        toAccountId: needsToAccount(type) ? toAccountId : null,
        debtId: needsDebt(type) ? debtId : null,
        tax: taxMap(),
      );

  /// Firestore line map, preserving an existing lineId when editing.
  Map<String, dynamic> toLineMap(int i, int micros) {
    final tax = taxMap();
    return {
      'lineId': lineId ?? 'l${i}_$micros',
      'type': type,
      'amount': amountValue,
      if (needsCategory(type)) 'categoryId': categoryId,
      if (needsToAccount(type)) 'toAccountId': toAccountId,
      if (needsDebt(type)) 'debtId': debtId,
      if (tax != null) 'tax': tax,
    };
  }

  void dispose() {
    amount.dispose();
    tds.dispose();
  }
}

/// Standard validation over a set of drafts (mirrors src/lib/txn.ts).
List<String> validateLineDrafts(List<LineDraft> drafts, {String? accountId, String? contactId}) {
  final errs = <String>[];
  if (accountId == null) errs.add('Pick an account.');
  final lines = [for (var i = 0; i < drafts.length; i++) drafts[i].toTxnLine(i)];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final n = i + 1;
    if (!(l.amount > 0)) errs.add('Line $n: amount must be greater than 0.');
    if (needsDebt(l.type) && l.debtId == null) {
      errs.add('Line $n: a ${kLineTypes[l.type]!.toLowerCase()} line must link a debt.');
    }
    if (l.type == 'transfer_in') {
      if (l.toAccountId == null) {
        errs.add('Line $n: a transfer-in line needs a destination account.');
      } else if (l.toAccountId == accountId) {
        errs.add('Line $n: transfer destination must differ from the source account.');
      }
    }
  }
  final linksDebt = lines.any((l) => needsDebt(l.type));
  if (linksDebt && contactId == null) {
    errs.add('Borrow / lend / repayment lines require a contact on the transaction.');
  }
  final outSum = lines.where((l) => l.type == 'transfer_out').fold<double>(0, (s, l) => s + l.amount);
  final inSum = lines.where((l) => l.type == 'transfer_in').fold<double>(0, (s, l) => s + l.amount);
  if ((outSum - inSum).abs() > 0.005) {
    errs.add('Transfer lines must balance: total transfer-out must equal total transfer-in.');
  }
  return errs;
}

/// The editable list of line cards. Parent owns the [lines]; this widget
/// renders them plus the "Lines / Add line" header and reports every mutation
/// through [onChanged].
class TxnLinesEditor extends StatelessWidget {
  final List<LineDraft> lines;
  final String? accountId;
  final VoidCallback onChanged;
  const TxnLinesEditor({
    super.key,
    required this.lines,
    required this.accountId,
    required this.onChanged,
  });

  void _addLine() {
    lines.add(LineDraft());
    onChanged();
  }

  void _removeLine(int i) {
    if (lines.length <= 1) return;
    lines.removeAt(i).dispose();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final accounts = data.accounts;
    final debts = data.debts.where((d) => d.purpose != 'shared').toList();
    final labelStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontSize: 12,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('LINES', style: labelStyle),
            TextButton.icon(
              onPressed: _addLine,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add line'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < lines.length; i++) _lineCard(context, i, data, accounts, debts),
      ],
    );
  }

  Widget _lineCard(BuildContext context, int i, DataController data, List<Account> accounts, List<Debt> debts) {
    final r = lines[i];
    final cats = data.categories
        .where((c) => c.kind == (isIncomeCategory(r.type) ? 'income' : 'expense'))
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
                    value: kLineTypes.containsKey(r.type) ? r.type : null,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      for (final e in kLineTypes.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) {
                      r.type = v ?? 'expense';
                      r.categoryId = null;
                      r.toAccountId = null;
                      r.debtId = null;
                      onChanged();
                    },
                  ),
                ),
                IconButton(
                  onPressed: lines.length > 1 ? () => _removeLine(i) : null,
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
              onChanged: (_) => onChanged(),
            ),
            if (needsCategory(r.type)) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: cats.any((c) => c.id == r.categoryId) ? r.categoryId : null,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) {
                  r.categoryId = v;
                  onChanged();
                },
              ),
            ],
            if (needsToAccount(r.type)) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: accounts.any((a) => a.id == r.toAccountId && a.id != accountId) ? r.toAccountId : null,
                decoration: const InputDecoration(labelText: 'To account'),
                items: [
                  for (final a in accounts.where((a) => a.id != accountId))
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) {
                  r.toAccountId = v;
                  onChanged();
                },
              ),
            ],
            if (needsDebt(r.type)) ...[
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
                onChanged: (v) {
                  r.debtId = v;
                  onChanged();
                },
              ),
              if (debts.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('No debts yet — create one under Debts first.',
                      style: TextStyle(fontSize: 12, color: Colors.orange)),
                ),
            ],
            if (canTax(r.type)) ...[
              const SizedBox(height: 8),
              _taxBlock(context, r),
            ],
          ],
        ),
      ),
    );
  }

  /// Compact per-line tax entry for income / interest_income lines. Mirrors the
  /// web TaxBlock: a "Tax info" toggle that reveals head / TDS / tax-inclusive.
  Widget _taxBlock(BuildContext context, LineDraft r) {
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
                onChanged: (v) {
                  r.taxable = v ?? false;
                  onChanged();
                },
              ),
              const Text('Tax info', style: TextStyle(fontSize: 13)),
            ],
          ),
          if (r.taxable) ...[
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: kTaxHeads.containsKey(r.taxHead) ? r.taxHead : null,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Head'),
              items: [
                for (final e in kTaxHeads.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                r.taxHead = v ?? 'other';
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: r.tds,
              decoration: const InputDecoration(labelText: 'TDS', prefixText: '₹ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Checkbox(
                  value: r.taxInclusive,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) {
                    r.taxInclusive = v ?? false;
                    onChanged();
                  },
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

/// Stable fingerprint of a draft line — used by form sheets to detect unsaved
/// edits (compared against a snapshot taken when the sheet opened).
String lineDraftFingerprint(LineDraft r) => [
      r.type,
      r.amount.text,
      r.categoryId,
      r.toAccountId,
      r.debtId,
      r.taxable,
      r.taxHead,
      r.tds.text,
      r.taxInclusive,
    ].join('|');
