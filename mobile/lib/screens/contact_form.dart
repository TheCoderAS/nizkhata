import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/workspace_controller.dart';

/// Open the create/edit contact sheet. Ports the web ContactDialog fields.
Future<void> showContactForm(BuildContext context, {Contact? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ContactForm(existing: existing),
    ),
  );
}

class _ContactForm extends StatefulWidget {
  final Contact? existing;
  const _ContactForm({this.existing});
  @override
  State<_ContactForm> createState() => _ContactFormState();
}

const _emailLabelOptions = ['Personal', 'Work', 'Other'];

/// One editable email row: a value controller + a label. Kept together so the
/// dynamic list can add/remove rows without losing per-field state.
class _EmailRow {
  final TextEditingController controller;
  String label;
  _EmailRow({String value = '', this.label = 'Personal'})
      : controller = TextEditingController(text: value);
}

class _ContactFormState extends State<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.existing?.address ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  late String _type = widget.existing?.type ?? 'person';
  late String _relationship = widget.existing?.relationship ?? 'external';
  late final List<_EmailRow> _emails = _seedEmails();
  bool _busy = false;

  List<_EmailRow> _seedEmails() {
    final existing = widget.existing;
    if (existing != null && existing.emails.isNotEmpty) {
      return existing.emails
          .map((e) => _EmailRow(
                value: e.value,
                label: _emailLabelOptions.contains(e.label) ? e.label : 'Other',
              ))
          .toList();
    }
    if (existing?.email != null && existing!.email!.isNotEmpty) {
      return [_EmailRow(value: existing.email!, label: 'Personal')];
    }
    return [];
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    for (final e in _emails) {
      e.controller.dispose();
    }
    super.dispose();
  }

  void _addEmail() =>
      setState(() => _emails.add(_EmailRow(label: _emailLabelOptions.first)));

  void _removeEmail(int i) {
    setState(() {
      _emails.removeAt(i).controller.dispose();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    final user = context.read<AuthController>().user;
    if (ws == null || user == null) return;
    setState(() => _busy = true);
    final m = Mutations(Actor.fromUser(user));
    // Drop blank rows; mutations normalize the shape and legacy `email` field.
    final emails = _emails
        .map((e) => {'value': e.controller.text.trim(), 'label': e.label})
        .where((e) => (e['value'] as String).isNotEmpty)
        .toList();
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'type': _type,
      'relationship': _relationship,
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'emails': emails,
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    };
    try {
      if (widget.existing == null) {
        await m.createContact(ws, data);
      } else {
        await m.updateContact(ws, widget.existing!.id, data);
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Contact saved')));
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'New contact' : 'Edit contact',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'person', label: Text('Person')),
                  ButtonSegment(value: 'business', label: Text('Business')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'external', label: Text('External')),
                  ButtonSegment(value: 'family', label: Text('Family')),
                ],
                selected: {_relationship},
                onSelectionChanged: (s) => setState(() => _relationship = s.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text('Emails',
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                  TextButton.icon(
                    onPressed: _addEmail,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add email'),
                  ),
                ],
              ),
              if (_emails.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'No emails added.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (int i = 0; i < _emails.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _emails[i].controller,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'name@example.com',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return null;
                            final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(value);
                            return ok ? null : '"$value" is not a valid email address';
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 116,
                        child: DropdownButtonFormField<String>(
                          initialValue: _emails[i].label,
                          isDense: true,
                          decoration: const InputDecoration(isDense: true),
                          items: _emailLabelOptions
                              .map((o) =>
                                  DropdownMenuItem(value: o, child: Text(o)))
                              .toList(),
                          onChanged: (v) => setState(
                              () => _emails[i].label = v ?? _emails[i].label),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove email',
                        icon: const Icon(Icons.close),
                        onPressed: () => _removeEmail(i),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Address (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                maxLines: 3,
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
