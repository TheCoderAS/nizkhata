import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/derive.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/discard_guard.dart';

const _kPurposeLabels = <String, String>{
  'loan': 'Loan',
  'custodial_savings': 'Custodial savings',
  'lending': 'Lending',
  'reimbursable': 'Reimbursable',
  'informal': 'Informal',
};

/// Create/edit debt sheet. Ports the web DebtDialog. On create it seeds an
/// opening-balance transaction; on edit only label/note/principal/status change.
Future<void> showDebtForm(BuildContext context, {Debt? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Guarded form: a swipe-down would pop the route without asking, so
    // dragging is off and DiscardGuard supplies the close button.
    showDragHandle: false,
    enableDrag: false,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _DebtForm(existing: existing),
    ),
  );
}

class _DebtForm extends StatefulWidget {
  final Debt? existing;
  const _DebtForm({this.existing});
  @override
  State<_DebtForm> createState() => _DebtFormState();
}

class _DebtFormState extends State<_DebtForm> {
  @override
  void initState() {
    super.initState();
    _fp0 = _fp();
  }

  // Unsaved-edit detection: snapshot on open, compare on close.
  late final String _fp0;
  String _fp() => ['$_contactId', _direction, _purpose, _label.text, _note.text, _opening.text, _interest.text, '$_accountId', _status].join('|');

  final _formKey = GlobalKey<FormState>();
  late String? _contactId = widget.existing?.contactId;
  late String _direction = widget.existing?.direction ?? 'owe';
  late String _purpose = widget.existing?.purpose ?? 'loan';
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late final _interest = TextEditingController(
      text: widget.existing?.interestRate != null ? widget.existing!.interestRate.toString() : '');
  late final _opening = TextEditingController(
      text: widget.existing != null ? widget.existing!.principal.toString() : '0');
  String? _accountId; // null = External / none
  late String _status = widget.existing?.status ?? 'open';
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    _opening.dispose();
    _interest.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_contactId == null) return;
    final wsC = context.read<WorkspaceController>();
    final ws = wsC.activeWorkspaceId;
    final fyStart = wsC.activeWorkspace?.fyStartMonth ?? 4;
    final user = context.read<AuthController>().user;
    if (ws == null || user == null) return;
    setState(() => _busy = true);
    final m = Mutations(Actor.fromUser(user));
    final amount = double.tryParse(_opening.text.trim()) ?? 0;
    try {
      if (_isEdit) {
        await m.updateDebt(ws, widget.existing!.id, {
          'label': _label.text.trim().isEmpty ? null : _label.text.trim(),
          'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
          'interestRate': double.tryParse(_interest.text.trim()),
          'principal': amount,
          'status': _status,
        });
      } else {
        await m.createDebtWithOpening(
          ws,
          fyStart,
          {
            'contactId': _contactId,
            'direction': _direction,
            'purpose': _purpose,
            'principal': amount,
            'label': _label.text.trim().isEmpty ? null : _label.text.trim(),
            'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
            'interestRate': double.tryParse(_interest.text.trim()),
            'interestFrom': widget.existing == null && double.tryParse(_interest.text.trim()) != null
                ? Timestamp.fromDate(DateTime.now())
                : null,
          },
          openingAmount: amount,
          accountId: _accountId,
          date: DateTime.now(),
          financialYearOf: financialYearOf,
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debt saved')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return DiscardGuard(
      title: _isEdit ? 'Edit debt' : 'New debt',
      isDirty: () => _fp() != _fp0,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final data = context.watch<DataController>();
    final contacts = data.contacts.where((c) => c.connectionUid == null).toList();
    final accounts = data.accounts;

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
              _sectionLabel('Terms'),
              DropdownButtonFormField<String>(
                value: _contactId,
                decoration: const InputDecoration(labelText: 'Contact'),
                items: [for (final c in contacts) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: _isEdit ? null : (v) => setState(() => _contactId = v),
                validator: (v) => v == null ? 'Pick a contact' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _direction,
                decoration: const InputDecoration(labelText: 'Direction'),
                items: const [
                  DropdownMenuItem(value: 'owe', child: Text('You owe them')),
                  DropdownMenuItem(value: 'owed', child: Text('They owe you')),
                ],
                onChanged: _isEdit ? null : (v) => setState(() => _direction = v ?? 'owe'),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _purpose,
                decoration: const InputDecoration(labelText: 'Purpose'),
                items: [
                  for (final e in _kPurposeLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: _isEdit ? null : (v) => setState(() => _purpose = v ?? 'loan'),
              ),
              const SizedBox(height: 22),
              _sectionLabel('Amount & notes'),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _opening,
                decoration: const InputDecoration(labelText: 'Opening amount', prefixText: '₹ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(value: 'settled', child: Text('Settled')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'open'),
                ),
              ] else ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _accountId,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('External / none')),
                    for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: (v) => setState(() => _accountId = v),
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _interest,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Interest rate (% p.a., optional)',
                  helperText: 'Simple interest, shown as an estimate. Never auto-posted.',
                ),
              ),
              if (_isEdit)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Contact, direction and purpose are fixed after creation to keep linked transactions consistent.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
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
