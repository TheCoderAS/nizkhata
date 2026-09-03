// Shared multi-line transaction editor — the typed lines (type / amount /
// category / to-account / debt / tax info) used by BOTH the transaction form
// and the due form, so a due is authored with exactly the same power as a
// transaction. State lives in [LineDraft]s owned by the parent form.
//
// A single line is edited inline, because most transactions are one line and
// a sheet-within-a-sheet would be ceremony for nothing. From the second line
// on, lines collapse to read-only summary rows and are edited in their own
// sheet: the parent form stays short and each line gets room to breathe.
// The sheet edits a COPY and writes back only on Done, so backing out of a
// line restores it (and a new line that is backed out leaves nothing behind).
//
// Transfers are authored as one line ("Transfer ... to <account>") even though
// the ledger stores the balancing transfer_out / transfer_in pair: see
// [draftsFromLines] and [lineMapsFromDrafts], which collapse and expand them.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import 'discard_guard.dart';
import 'row_actions.dart';

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

/// What the type picker offers. `transfer_in` is absent on purpose: a transfer
/// is authored as one line that names its destination, and the matching
/// in-line is generated on save. A legacy unpaired in-line stays editable —
/// [lineTypeLabel] still names it, it just cannot be chosen afresh.
const kSelectableLineTypes = <String, String>{
  'income': 'Income',
  'expense': 'Expense',
  'transfer_out': 'Transfer',
  'borrow': 'Borrow',
  'lend': 'Lend',
  'repayment': 'Repayment',
  'fee': 'Fee',
  'interest_income': 'Interest income',
  'interest_expense': 'Interest expense',
  'tax': 'Tax / GST',
};

String lineTypeLabel(String type) => kSelectableLineTypes[type] ?? kLineTypes[type] ?? type;

bool needsCategory(String type) =>
    type == 'income' ||
    type == 'expense' ||
    type == 'fee' ||
    type == 'tax' ||
    type == 'interest_income' ||
    type == 'interest_expense';

bool isIncomeCategory(String type) => type == 'income' || type == 'interest_income';

/// Both transfer directions name another account: the authored transfer line
/// (transfer_out) says where the money lands, and a legacy in-line says where
/// it landed.
bool needsToAccount(String type) => type == 'transfer_out' || type == 'transfer_in';

bool isTransfer(String type) => type == 'transfer_out' || type == 'transfer_in';

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
  // For an authored transfer: the id of the generated transfer_in line, so an
  // edit rewrites the same pair instead of orphaning it.
  String? pairLineId;
  // Per-line tax entry (only meaningful for income / interest_income lines).
  bool taxable = false;
  String taxHead = 'other';
  final TextEditingController tds = TextEditingController();
  bool taxInclusive = false;
  LineDraft({this.type = 'expense', this.lineId, this.pairLineId});

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

  /// An independent copy, controllers and all — what the line sheet edits so
  /// that backing out leaves the original untouched.
  LineDraft copy() {
    final c = LineDraft(type: type, lineId: lineId, pairLineId: pairLineId);
    c.amount.text = amount.text;
    c.categoryId = categoryId;
    c.toAccountId = toAccountId;
    c.debtId = debtId;
    c.taxable = taxable;
    c.taxHead = taxHead;
    c.tds.text = tds.text;
    c.taxInclusive = taxInclusive;
    return c;
  }

  /// Adopt every field of [o] — how a committed sheet writes back.
  void applyFrom(LineDraft o) {
    type = o.type;
    amount.text = o.amount.text;
    categoryId = o.categoryId;
    toAccountId = o.toAccountId;
    debtId = o.debtId;
    lineId = o.lineId;
    pairLineId = o.pairLineId;
    taxable = o.taxable;
    taxHead = o.taxHead;
    tds.text = o.tds.text;
    taxInclusive = o.taxInclusive;
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
        // The out-leg of an authored transfer carries no destination: its
        // generated in-leg does (that is what credits the other account).
        toAccountId: type == 'transfer_in' ? toAccountId : null,
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
      if (type == 'transfer_in') 'toAccountId': toAccountId,
      if (needsDebt(type)) 'debtId': debtId,
      if (tax != null) 'tax': tax,
    };
  }

  void dispose() {
    amount.dispose();
    tds.dispose();
  }
}

// ---- collapse / expand transfers -------------------------------------------

/// Stored lines to editable drafts, collapsing each transfer_out and its
/// matching transfer_in into ONE transfer draft. Anything that doesn't pair
/// (older or hand-edited data) stays as its own draft so it remains fixable.
List<LineDraft> draftsFromLines(List<TxnLine> lines) {
  final consumed = <int>{};
  final drafts = <LineDraft>[];
  for (var i = 0; i < lines.length; i++) {
    if (consumed.contains(i)) continue;
    final l = lines[i];
    if (l.type == 'transfer_out') {
      // First unclaimed in-line of the same amount is this transfer's other
      // half. Several transfers in one transaction pair up in order.
      var pairIndex = -1;
      for (var j = 0; j < lines.length; j++) {
        if (j == i || consumed.contains(j)) continue;
        if (lines[j].type == 'transfer_in' && (lines[j].amount - l.amount).abs() < 0.005) {
          pairIndex = j;
          break;
        }
      }
      if (pairIndex >= 0) {
        final pair = lines[pairIndex];
        consumed.add(pairIndex);
        final d = LineDraft(type: 'transfer_out', lineId: l.lineId, pairLineId: pair.lineId);
        d.amount.text = amountText(l.amount);
        d.toAccountId = pair.toAccountId;
        drafts.add(d);
        continue;
      }
    }
    drafts.add(LineDraft.fromLine(l));
  }
  return drafts;
}

/// Drafts to engine lines, expanding each authored transfer back into its
/// balancing pair so totals and validation see what will actually be stored.
List<TxnLine> txnLinesFromDrafts(List<LineDraft> drafts) {
  final out = <TxnLine>[];
  for (var i = 0; i < drafts.length; i++) {
    final d = drafts[i];
    out.add(d.toTxnLine(i));
    if (d.type == 'transfer_out') {
      out.add(TxnLine(
        lineId: 'l${i}b',
        type: 'transfer_in',
        amount: d.amountValue,
        toAccountId: d.toAccountId,
      ));
    }
  }
  return out;
}

/// Drafts to Firestore line maps, expanding transfers the same way and reusing
/// both stored ids so an edit rewrites the pair in place.
List<Map<String, dynamic>> lineMapsFromDrafts(List<LineDraft> drafts, int micros) {
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < drafts.length; i++) {
    final d = drafts[i];
    out.add(d.toLineMap(i, micros));
    if (d.type == 'transfer_out') {
      out.add({
        'lineId': d.pairLineId ?? 'l${i}b_$micros',
        'type': 'transfer_in',
        'amount': d.amountValue,
        'toAccountId': d.toAccountId,
      });
    }
  }
  return out;
}

// ---- validation ------------------------------------------------------------

/// What's wrong with ONE line, phrased for the line sheet (no line numbers —
/// the sheet is already about this line).
List<String> validateLineDraft(
  LineDraft d, {
  String? accountId,
  String? contactId,
  Map<String, Debt>? debtsById,
}) {
  final errs = <String>[];
  if (!(d.amountValue > 0)) errs.add('Enter an amount greater than 0.');
  if (needsDebt(d.type)) {
    if (contactId == null) {
      errs.add('Pick a contact on the transaction before linking a debt.');
    } else if (d.debtId == null) {
      errs.add('Link the debt this line settles.');
    } else if (debtsById != null) {
      final debt = debtsById[d.debtId];
      if (debt != null && debt.contactId != contactId) {
        errs.add('That debt belongs to someone else. Pick one of this contact\'s debts.');
      }
    }
  }
  if (needsToAccount(d.type)) {
    if (d.toAccountId == null) {
      errs.add('Choose the account the money moves to.');
    } else if (d.toAccountId == accountId) {
      errs.add('The destination must differ from the account above.');
    }
  }
  return errs;
}

/// Standard validation over a set of drafts (mirrors src/lib/txn.ts), with the
/// per-line problems numbered and the cross-line rules on top.
List<String> validateLineDrafts(
  List<LineDraft> drafts, {
  String? accountId,
  String? contactId,
  Map<String, Debt>? debtsById,
}) {
  final errs = <String>[];
  if (accountId == null) errs.add('Pick an account.');
  for (var i = 0; i < drafts.length; i++) {
    for (final e
        in validateLineDraft(drafts[i], accountId: accountId, contactId: contactId, debtsById: debtsById)) {
      errs.add('Line ${i + 1}: ${e[0].toLowerCase()}${e.substring(1)}');
    }
  }
  // Authored transfers always balance by construction; this still catches
  // legacy lines that were stored unpaired.
  final lines = txnLinesFromDrafts(drafts);
  final outSum = lines.where((l) => l.type == 'transfer_out').fold<double>(0, (s, l) => s + l.amount);
  final inSum = lines.where((l) => l.type == 'transfer_in').fold<double>(0, (s, l) => s + l.amount);
  if ((outSum - inSum).abs() > 0.005) {
    errs.add('Transfer lines must balance: total transfer-out must equal total transfer-in.');
  }
  return errs;
}

// ---- pickers ---------------------------------------------------------------

/// How a debt reads in a picker: its label (or the contact's name) plus which
/// way it runs.
String debtPickerLabel(Debt d, Map<String, Contact> contactsById) =>
    '${d.label ?? contactsById[d.contactId]?.name ?? 'Debt'}'
    ' · ${d.direction == 'owe' ? 'payable' : 'receivable'}';

/// Debts a line may link: this contact's own debts, name-sorted. Shared-expense
/// debts are managed by the shared ledger, never hand-picked here.
List<Debt> debtsForContact(
  List<Debt> all,
  String? contactId,
  Map<String, Contact> contactsById,
) {
  if (contactId == null) return const [];
  final list = all.where((d) => d.purpose != 'shared' && d.contactId == contactId).toList()
    ..sort((a, b) => debtPickerLabel(a, contactsById)
        .toLowerCase()
        .compareTo(debtPickerLabel(b, contactsById).toLowerCase()));
  return list;
}

// ---- summary ---------------------------------------------------------------

/// What the line points at, for its summary row: the category, the account the
/// money moves to, or the debt it settles.
String lineTargetLabel(LineDraft d, DataController data) {
  if (needsCategory(d.type)) {
    return data.categoriesById[d.categoryId]?.name ?? 'No category';
  }
  if (needsToAccount(d.type)) {
    final name = data.accountsById[d.toAccountId]?.name;
    return name == null ? 'No destination' : 'to $name';
  }
  if (needsDebt(d.type)) {
    final debt = data.debtsById[d.debtId];
    return debt == null ? 'No debt linked' : debtPickerLabel(debt, data.contactsById);
  }
  return '';
}

/// The line's signed effect on the transaction's own account — a transfer
/// counts once (the money leaves), since its in-leg credits the other account.
double draftSignedAmount(LineDraft d, Map<String, Debt> debtsById) {
  var total = 0.0;
  for (final l in txnLinesFromDrafts([d])) {
    total += primaryAccountEffect(l, l.debtId != null ? debtsById[l.debtId] : null);
  }
  return roundMoney(total);
}

// ---- the editor ------------------------------------------------------------

/// The list of lines on a form. One line is edited inline; two or more become
/// summary rows that open the line sheet. The parent owns [lines] and is told
/// about every change through [onChanged].
class TxnLinesEditor extends StatelessWidget {
  final List<LineDraft> lines;
  final String? accountId;
  final String? contactId;
  final VoidCallback onChanged;
  const TxnLinesEditor({
    super.key,
    required this.lines,
    required this.accountId,
    required this.contactId,
    required this.onChanged,
  });

  Future<void> _addLine(BuildContext context) async {
    final draft = LineDraft(type: 'expense');
    final action = await showLineEditorSheet(
      context,
      draft: draft,
      isNew: true,
      accountId: accountId,
      contactId: contactId,
      canDelete: false,
    );
    if (action == LineEditorAction.save) {
      lines.add(draft); // ownership passes to the parent form
      onChanged();
    } else {
      draft.dispose();
    }
  }

  Future<void> _editLine(BuildContext context, int i) async {
    final copy = lines[i].copy();
    final action = await showLineEditorSheet(
      context,
      draft: copy,
      isNew: false,
      accountId: accountId,
      contactId: contactId,
      canDelete: lines.length > 1,
    );
    if (action == LineEditorAction.save) {
      lines[i].applyFrom(copy);
      onChanged();
    } else if (action == LineEditorAction.delete) {
      lines.removeAt(i).dispose();
      onChanged();
    }
    copy.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final labelStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontSize: 12,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    final single = lines.length == 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('LINES', style: labelStyle),
            TextButton.icon(
              onPressed: () => _addLine(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add line'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (single)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: LineFields(
                draft: lines.first,
                accountId: accountId,
                contactId: contactId,
                onChanged: onChanged,
              ),
            ),
          )
        else
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _summaryRow(context, data, i),
            ),
      ],
    );
  }

  Widget _summaryRow(BuildContext context, DataController data, int i) {
    final d = lines[i];
    final cs = Theme.of(context).colorScheme;
    final currency = context.watch<WorkspaceController>().activeWorkspace?.baseCurrency ?? 'INR';
    final signed = draftSignedAmount(d, data.debtsById);
    final target = lineTargetLabel(d, data);
    final problems =
        validateLineDraft(d, accountId: accountId, contactId: contactId, debtsById: data.debtsById);

    final card = Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _editLine(context, i),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lineTypeLabel(d.type),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    if (target.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(target,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                      ),
                    if (d.taxable)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Tax: ${kTaxHeads[d.taxHead] ?? d.taxHead}',
                            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                      ),
                    if (problems.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(problems.first,
                            style: const TextStyle(fontSize: 11.5, color: AppColors.danger)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatMoney(signed, currency),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: signed < 0 ? AppColors.danger : AppColors.accent2,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return RowActions(
      id: 'line-$i',
      title: '${lineTypeLabel(d.type)}${target.isEmpty ? '' : ' · $target'}',
      swipeStart:
          RowAction(icon: Icons.edit_outlined, label: 'Edit line', onTap: () => _editLine(context, i)),
      menu: [
        RowAction(icon: Icons.edit_outlined, label: 'Edit line', onTap: () => _editLine(context, i)),
        if (lines.length > 1)
          RowAction(
            icon: Icons.delete_outline,
            label: 'Remove line',
            destructive: true,
            onTap: () {
              lines.removeAt(i).dispose();
              onChanged();
            },
          ),
      ],
      child: card,
    );
  }
}

/// The fields of one line. Used inline for a single-line transaction and
/// inside the line sheet for a split, so both behave identically.
class LineFields extends StatelessWidget {
  final LineDraft draft;
  final String? accountId;
  final String? contactId;
  final VoidCallback onChanged;
  const LineFields({
    super.key,
    required this.draft,
    required this.accountId,
    required this.contactId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final r = draft;
    final cats =
        data.categories.where((c) => c.kind == (isIncomeCategory(r.type) ? 'income' : 'expense')).toList();
    final debts = debtsForContact(data.debts, contactId, data.contactsById);
    final destinations = data.accounts.where((a) => a.id != accountId).toList();
    // A type that is no longer offered (a legacy transfer_in) still has to
    // show as the current value, so it joins the list for this line only.
    final typeItems = {
      ...kSelectableLineTypes,
      if (!kSelectableLineTypes.containsKey(r.type)) r.type: kLineTypes[r.type] ?? r.type,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: typeItems.containsKey(r.type) ? r.type : null,
          decoration: const InputDecoration(labelText: 'Type'),
          items: [
            for (final e in typeItems.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            r.type = v ?? 'expense';
            r.categoryId = null;
            r.toAccountId = null;
            r.debtId = null;
            onChanged();
          },
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: r.amount,
          decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => onChanged(),
        ),
        if (needsCategory(r.type)) ...[
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: destinations.any((a) => a.id == r.toAccountId) ? r.toAccountId : null,
            decoration: InputDecoration(
              labelText: 'To account',
              helperText:
                  r.type == 'transfer_out' ? 'The money leaves the account above and lands here.' : null,
            ),
            items: [
              for (final a in destinations) DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) {
              r.toAccountId = v;
              onChanged();
            },
          ),
          if (destinations.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('A transfer needs a second account. Add one under Accounts.',
                  style: TextStyle(fontSize: 12, color: Colors.orange)),
            ),
        ],
        if (needsDebt(r.type)) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: debts.any((d) => d.id == r.debtId) ? r.debtId : null,
            decoration: const InputDecoration(labelText: 'Debt'),
            items: [
              for (final d in debts)
                DropdownMenuItem(value: d.id, child: Text(debtPickerLabel(d, data.contactsById))),
            ],
            onChanged: (v) {
              r.debtId = v;
              onChanged();
            },
          ),
          if (contactId == null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Pick a contact on the transaction to choose one of their debts.',
                  style: TextStyle(fontSize: 12, color: Colors.orange)),
            )
          else if (debts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('This contact has no debts yet. Create one under Debts first.',
                  style: TextStyle(fontSize: 12, color: Colors.orange)),
            ),
        ],
        if (canTax(r.type)) ...[
          const SizedBox(height: 10),
          _taxBlock(context, r),
        ],
      ],
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
                for (final e in kTaxHeads.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
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

enum LineEditorAction { save, delete }

/// The line sheet, stacked on the form. Edits [draft] (already a copy) and
/// reports what the user chose; the caller writes back or throws it away.
Future<LineEditorAction?> showLineEditorSheet(
  BuildContext context, {
  required LineDraft draft,
  required bool isNew,
  required String? accountId,
  required String? contactId,
  required bool canDelete,
}) {
  return showModalBottomSheet<LineEditorAction>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    // Guarded form: a swipe-down would pop the route without asking, so
    // dragging is off and DiscardGuard supplies the close button.
    showDragHandle: false,
    enableDrag: false,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _LineEditorSheet(
        draft: draft,
        isNew: isNew,
        accountId: accountId,
        contactId: contactId,
        canDelete: canDelete,
      ),
    ),
  );
}

class _LineEditorSheet extends StatefulWidget {
  final LineDraft draft;
  final bool isNew;
  final String? accountId;
  final String? contactId;
  final bool canDelete;
  const _LineEditorSheet({
    required this.draft,
    required this.isNew,
    required this.accountId,
    required this.contactId,
    required this.canDelete,
  });

  @override
  State<_LineEditorSheet> createState() => _LineEditorSheetState();
}

class _LineEditorSheetState extends State<_LineEditorSheet> {
  late final String _fp0 = lineDraftFingerprint(widget.draft);

  @override
  Widget build(BuildContext context) {
    return DiscardGuard(
      title: widget.isNew ? 'New line' : 'Edit line',
      isDirty: () => lineDraftFingerprint(widget.draft) != _fp0,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final data = context.watch<DataController>();
    final errors = validateLineDraft(
      widget.draft,
      accountId: widget.accountId,
      contactId: widget.contactId,
      debtsById: data.debtsById,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: kSheetFieldTopPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LineFields(
                draft: widget.draft,
                accountId: widget.accountId,
                contactId: widget.contactId,
                onChanged: () => setState(() {}),
              ),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final e in errors)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(e, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                  ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  if (widget.canDelete) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(LineEditorAction.delete),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          minimumSize: const Size.fromHeight(46),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          errors.isEmpty ? () => Navigator.of(context).pop(LineEditorAction.save) : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
