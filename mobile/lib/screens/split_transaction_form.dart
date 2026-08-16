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
import '../widgets/txn_lines_editor.dart';

/// THE transaction sheet — create and edit. One form for everything: a header
/// (date / account / contact / note) plus a dynamic list of typed lines with
/// "Add line" (single-line by default, split when you add more), including
/// per-line tax info. Signed total and validation mirror the web engine.
Future<void> showSplitTransactionForm(BuildContext context, {Txn? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Own context for MediaQuery — the caller's may be unmounted when this is
    // opened right after the detail sheet pops on Edit (would blank the sheet).
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _TransactionForm(existing: existing),
    ),
  );
}

class _TransactionForm extends StatefulWidget {
  final Txn? existing;
  const _TransactionForm({this.existing});
  @override
  State<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<_TransactionForm> {
  DateTime _date = DateTime.now();
  String? _accountId;
  String? _contactId;
  final _note = TextEditingController();
  late final List<LineDraft> _lines;
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
      _lines = [for (final l in txn.lines) LineDraft.fromLine(l)];
      if (_lines.isEmpty) _lines.add(LineDraft(type: 'expense'));
    } else {
      // Start simple: one line. "Add line" turns it into a split.
      _lines = [LineDraft(type: 'expense')];
    }
  }

  @override
  void dispose() {
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  List<TxnLine> _txnLines() => [for (var i = 0; i < _lines.length; i++) _lines[i].toTxnLine(i)];

  Future<void> _save() async {
    final wsC = context.read<WorkspaceController>();
    final ws = wsC.activeWorkspaceId;
    final fyStart = wsC.activeWorkspace?.fyStartMonth ?? 4;
    final user = context.read<AuthController>().user;
    final data = context.read<DataController>();
    if (ws == null || user == null || _accountId == null) return;
    if (validateLineDrafts(_lines, accountId: _accountId, contactId: _contactId).isNotEmpty) return;

    final micros = DateTime.now().microsecondsSinceEpoch;
    final lines = [for (var i = 0; i < _lines.length; i++) _lines[i].toLineMap(i, micros)];

    // Header contact wins; otherwise fall back to a debt line's contact.
    String? contactId = _contactId;
    if (contactId == null) {
      for (final r in _lines) {
        if (needsDebt(r.type) && r.debtId != null) {
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
    final contacts = data.contacts.where((c) => c.connectionUid == null).toList();

    final total = computeTotal(_txnLines(), data.debtsById);
    final errors = validateLineDrafts(_lines, accountId: _accountId, contactId: _contactId);
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
              Text(_isEditing ? 'Edit transaction' : 'New transaction',
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
              TxnLinesEditor(
                lines: _lines,
                accountId: _accountId,
                onChanged: () => setState(() {}),
              ),
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

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontSize: 12,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
}
