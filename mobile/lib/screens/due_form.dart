import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../services/recurrence.dart';
import '../services/title_tokens.dart';
import '../widgets/token_assist.dart';
import '../widgets/txn_lines_editor.dart';
import '../widgets/discard_guard.dart';
import '../widgets/common.dart';

/// Create/edit due sheet — a due is authored exactly like a transaction: the
/// same multi-line editor (typed lines, categories, tax info), plus a due date
/// and direction. The amount is the computed total of the lines; settling the
/// due materializes these lines into the real transaction.
Future<void> showDueForm(BuildContext context,
    {Due? existing, DateTime? initialDate}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    // Guarded form: a swipe-down would pop the route without asking, so
    // dragging is off and DiscardGuard supplies the close button.
    showDragHandle: false,
    enableDrag: false,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _DueForm(existing: existing, initialDate: initialDate),
    ),
  );
}

class _DueForm extends StatefulWidget {
  final Due? existing;

  /// Due date to start on when creating — the calendar opens the form on the
  /// day that was tapped.
  final DateTime? initialDate;
  const _DueForm({this.existing, this.initialDate});
  @override
  State<_DueForm> createState() => _DueFormState();
}

class _DueFormState extends State<_DueForm> {
  // Unsaved-edit detection: snapshot on open, compare on close.
  late final String _fp0;
  String _fp() => [_title.text, _dueDate.toIso8601String(), '$_contactId', '$_accountId', _note.text, _recurrence, for (final r in _lines) lineDraftFingerprint(r)].join('|');

  final _formKey = GlobalKey<FormState>();
  // The fields hold the PATTERN — what the user typed, tokens and all. The
  // rendered text is derived on save; an entry with no tokens has no pattern
  // stored and behaves exactly as before.
  late final _title = TextEditingController(
      text: widget.existing?.titlePattern ?? widget.existing?.title ?? '');
  late DateTime _dueDate =
      widget.existing?.dueDate ?? widget.initialDate ?? DateTime.now();
  late String _recurrence = widget.existing?.recurrence ?? '';
  late String? _contactId = widget.existing?.contactId;
  late String? _accountId = widget.existing?.accountId;
  late final _note = TextEditingController(
      text: widget.existing?.notePattern ?? widget.existing?.note ?? '');
  late final List<LineDraft> _lines;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final due = widget.existing;
    if (due != null && due.lines.isNotEmpty) {
      // Transfers are stored as a balancing pair but authored as one line.
      _lines = draftsFromLines(due.lines);
    } else if (due != null) {
      // Legacy single-amount due → synthesize one line from its fields.
      final row = LineDraft(type: due.direction == 'payable' ? 'expense' : 'income');
      row.amount.text = amountText(due.amount);
      row.categoryId = due.categoryId;
      _lines = [row];
    } else {
      // New due defaults to a payable (expense) line; switch the line type to
      // income to make it a receivable — direction is derived from the lines.
      _lines = [LineDraft(type: 'expense')];
    }
    _fp0 = _fp();
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  List<TxnLine> _txnLines() => txnLinesFromDrafts(_lines);

  /// A debt line may only point at the chosen contact's debts, so switching
  /// contact drops any link that no longer belongs to them.
  void _dropForeignDebtLinks(DataController data) {
    for (final l in _lines) {
      if (!needsDebt(l.type) || l.debtId == null) continue;
      if (data.debtsById[l.debtId]?.contactId != _contactId) l.debtId = null;
    }
  }

  /// Due-specific validation: the transaction rules minus the account
  /// requirement (a due's account is optional until it's actually paid).
  List<String> _errors() => validateLineDrafts(_lines, accountId: _accountId, contactId: _contactId)
      .where((e) => e != 'Pick an account.')
      .toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_errors().isNotEmpty) return;
    final wsC = context.read<WorkspaceController>();
    final ws = wsC.activeWorkspaceId;
    final user = context.read<AuthController>().user;
    final dataC = context.read<DataController>();
    if (ws == null || user == null) return;

    final signedTotal = computeTotal(_txnLines(), dataC.debtsById);
    if (signedTotal.abs() <= 0.005) return;
    // Direction is DERIVED from the lines' computed total, so the stored value
    // can never contradict what settling will actually post. The toggle is just
    // an authoring preset for line types.
    final direction = signedTotal < 0 ? 'payable' : 'receivable';

    setState(() => _busy = true);
    final m = Mutations(Actor.fromUser(user));
    final fyStart = wsC.activeWorkspace?.fyStartMonth ?? 4;
    final occurrence = widget.existing?.occurrence ?? 1;
    final titlePattern = _title.text.trim();
    final notePattern = _note.text.trim();
    final note = notePattern.isEmpty
        ? null
        : renderTokens(notePattern, _dueDate,
            occurrence: occurrence, fyStartMonth: fyStart);
    final micros = DateTime.now().microsecondsSinceEpoch;
    final lineMaps = lineMapsFromDrafts(_lines, micros);
    // First categorised line doubles as the legacy categoryId (web back-compat).
    String? firstCategory;
    for (final l in lineMaps) {
      if (l['categoryId'] != null) {
        firstCategory = l['categoryId'] as String;
        break;
      }
    }
    final data = <String, dynamic>{
      'direction': direction,
      'title': renderTokens(titlePattern, _dueDate,
          occurrence: occurrence, fyStartMonth: fyStart),
      // Stored only when it actually carries tokens, so a plain title leaves
      // no trace of a feature it never used.
      'titlePattern': hasTokens(titlePattern) ? titlePattern : null,
      'notePattern': hasTokens(notePattern) ? notePattern : null,
      'occurrence': occurrence,
      'amount': roundMoney(signedTotal.abs()),
      'dueDate': Timestamp.fromDate(_dueDate),
      'contactId': _contactId,
      'accountId': _accountId,
      'categoryId': firstCategory,
      'note': note,
      'lines': lineMaps,
      'recurrence': _recurrence.isEmpty ? null : _recurrence,
      'recurrenceId': _recurrence.isEmpty
          ? null
          : (widget.existing?.recurrenceId ?? widget.existing?.id),
    };
    try {
      if (widget.existing == null) {
        await m.createDue(ws, data);
      } else {
        await m.updateDue(ws, widget.existing!.id, data);
        // Cascade to any transactions already settled from this due — their
        // lines are replaced by the due's lines scaled to each paid magnitude.
        final linked = dataC.transactions.where((t) => t.dueId == widget.existing!.id).toList();
        final title = data['title'] as String;
        await m.syncDueLinkedTxns(
          ws,
          linked: linked,
          direction: direction,
          note: note ?? (title.isEmpty ? null : title),
          contactId: _contactId,
          dueLines: lineMaps,
          dueSignedTotal: signedTotal,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Due saved')));
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
      title: widget.existing == null ? 'New due' : 'Edit due',
      isDirty: () => _fp() != _fp0,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final contacts = data.contacts.where((c) => c.connectionUid == null).toList();
    final accounts = data.accounts;

    final signedTotal = computeTotal(_txnLines(), data.debtsById);
    final errors = _errors();

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: kSheetFieldTopPad),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              // Placeholders only make sense once the due repeats, so the
              // strip appears with the repeat and not before.
              if (_recurrence.isNotEmpty)
                TokenAssist(
                  controller: _title,
                  nextDate: nextOccurrence(_dueDate, _recurrence),
                  fyStartMonth: ws.activeWorkspace?.fyStartMonth ?? 4,
                ),
              const SizedBox(height: 14),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dueDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _dueDate = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Due date'),
                  child: Text(formatDate(_dueDate)),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
                textCapitalization: TextCapitalization.sentences,
              ),
              if (_recurrence.isNotEmpty)
                TokenAssist(
                  controller: _note,
                  nextDate: nextOccurrence(_dueDate, _recurrence),
                  fyStartMonth: ws.activeWorkspace?.fyStartMonth ?? 4,
                  previewLabel: 'Next note',
                ),
              const SizedBox(height: 16),
              // Same line editor as the transaction form — types, categories,
              // tax info, add/remove lines.
              TxnLinesEditor(
                lines: _lines,
                accountId: _accountId,
                contactId: _contactId,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Due amount', style: TextStyle(fontWeight: FontWeight.w600)),
                    // Amount + the direction DERIVED from the lines (what will
                    // actually be stored/settled) — so the form can't mislead.
                    Text(
                      '${formatMoney(signedTotal.abs(), currency)}'
                      '${signedTotal.abs() > 0.005 ? (signedTotal < 0 ? '  ·  you\'ll pay' : '  ·  you\'ll receive') : ''}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: signedTotal < 0 ? AppColors.danger : AppColors.accent2,
                      ),
                    ),
                  ],
                ),
              ),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final e in errors)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(e, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                  ),
              ],
              const SizedBox(height: 22),
              SectionLabel('Linked to (optional)'),
              DropdownButtonFormField<String>(
                value: _recurrence,
                decoration: const InputDecoration(labelText: 'Repeats'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Does not repeat')),
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                ],
                onChanged: (v) => setState(() => _recurrence = v ?? ''),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: contacts.any((c) => c.id == _contactId) ? _contactId : null,
                decoration: const InputDecoration(labelText: 'Contact (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final c in contacts) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() {
                  _contactId = v;
                  _dropForeignDebtLinks(context.read<DataController>());
                }),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: accounts.any((a) => a.id == _accountId) ? _accountId : null,
                decoration: const InputDecoration(labelText: 'Account (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_busy || errors.isNotEmpty || signedTotal.abs() <= 0.005) ? null : _save,
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
