import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';

/// Create/edit due sheet. Ports the web DueDialog fields.
Future<void> showDueForm(BuildContext context, {Due? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _DueForm(existing: existing),
    ),
  );
}

class _DueForm extends StatefulWidget {
  final Due? existing;
  const _DueForm({this.existing});
  @override
  State<_DueForm> createState() => _DueFormState();
}

class _DueFormState extends State<_DueForm> {
  final _formKey = GlobalKey<FormState>();
  late String _direction = widget.existing?.direction ?? 'payable';
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _amount = TextEditingController(
      text: widget.existing != null ? widget.existing!.amount.toString() : '0');
  late DateTime _dueDate = widget.existing?.dueDate ?? DateTime.now();
  late String? _contactId = widget.existing?.contactId;
  late String? _accountId = widget.existing?.accountId;
  late String? _categoryId = widget.existing?.categoryId;
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    final user = context.read<AuthController>().user;
    final dataC = context.read<DataController>();
    if (ws == null || user == null) return;
    setState(() => _busy = true);
    final m = Mutations(Actor.fromUser(user));
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final data = <String, dynamic>{
      'direction': _direction,
      'title': _title.text.trim(),
      'amount': double.tryParse(_amount.text.trim()) ?? 0,
      'dueDate': Timestamp.fromDate(_dueDate),
      'contactId': _contactId,
      'accountId': _accountId,
      'categoryId': _categoryId,
      'note': note,
    };
    try {
      if (widget.existing == null) {
        await m.createDue(ws, data);
      } else {
        await m.updateDue(ws, widget.existing!.id, data);
        // Cascade the descriptive fields to any transactions already settled
        // from this due, so the due stays the source of truth.
        final linked = dataC.transactions.where((t) => t.dueId == widget.existing!.id).toList();
        final title = _title.text.trim();
        await m.syncDueLinkedTxns(
          ws,
          linked: linked,
          direction: _direction,
          categoryId: _categoryId,
          // Mirror the settle flow's note (note, falling back to the title).
          note: note ?? (title.isEmpty ? null : title),
          contactId: _contactId,
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
    final data = context.watch<DataController>();
    final contacts = data.contacts.where((c) => c.connectionUid == null).toList();
    final accounts = data.accounts;
    // Category list follows the direction: payable settles as an expense,
    // receivable as income — same split the transaction form uses.
    final cats = data.categories
        .where((c) => c.kind == (_direction == 'payable' ? 'expense' : 'income'))
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'New due' : 'Edit due',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'payable', label: Text('Payable')),
                  ButtonSegment(value: 'receivable', label: Text('Receivable')),
                ],
                selected: {_direction},
                onSelectionChanged: (s) => setState(() => _direction = s.first),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amount,
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) =>
                    (double.tryParse(v?.trim() ?? '') ?? 0) <= 0 ? 'Enter an amount greater than 0' : null,
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
              DropdownButtonFormField<String>(
                // Guard a stale/mismatched category (e.g. after switching
                // direction) so the field never trips the dropdown assertion.
                value: cats.any((c) => c.id == _categoryId) ? _categoryId : null,
                decoration: const InputDecoration(labelText: 'Category (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 22),
              _sectionLabel('Linked to (optional)'),
              DropdownButtonFormField<String>(
                value: _contactId,
                decoration: const InputDecoration(labelText: 'Contact (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final c in contacts) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _contactId = v),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _accountId,
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
