// Role create/edit sheet — ports the RoleEditor from src/pages/Roles.tsx.
// Name field + grouped permission checkboxes; dangerous perms warn in amber.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/mutations.dart';
import '../data/permissions.dart';
import '../state/auth_controller.dart';
import '../state/workspace_controller.dart';

const _amber = Color(0xFFF59E0B);

class _PermGroup {
  final String label;
  final String prefix;
  const _PermGroup(this.label, this.prefix);
}

const _permGroups = <_PermGroup>[
  _PermGroup('Transactions', 'transactions.'),
  _PermGroup('Accounts', 'accounts.'),
  _PermGroup('Categories', 'categories.'),
  _PermGroup('Contacts', 'contacts.'),
  _PermGroup('Debts', 'debts.'),
  _PermGroup('Dues', 'dues.'),
  _PermGroup('Shared', 'shared.'),
  _PermGroup('Reports', 'reports.'),
  _PermGroup('Members', 'members.'),
  _PermGroup('Roles', 'roles.'),
  _PermGroup('Workspace', 'workspace.'),
];

/// Open the create/edit role sheet.
Future<void> showRoleEditor(BuildContext context, {Role? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _RoleForm(existing: existing),
    ),
  );
}

class _RoleForm extends StatefulWidget {
  final Role? existing;
  const _RoleForm({this.existing});
  @override
  State<_RoleForm> createState() => _RoleFormState();
}

class _RoleFormState extends State<_RoleForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final Map<String, bool> _perms = {...(widget.existing?.permissions ?? {})};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ws = context.read<WorkspaceController>();
    final wsId = ws.activeWorkspaceId;
    final user = context.read<AuthController>().user;
    if (wsId == null || user == null) return;
    setState(() => _busy = true);
    final m = Mutations(Actor.fromUser(user));
    final name = _name.text.trim();
    final perms = {for (final p in kPermissions) if (_perms[p] == true) p: true};
    try {
      if (widget.existing == null) {
        await m.createRole(wsId, name, perms);
      } else {
        await m.updateRole(widget.existing!.id, name: name, permissions: perms);
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Role saved')));
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
    final cs = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'New role' : 'Edit role',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (final group in _permGroups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                        child: Text(
                          group.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      for (final p in kPermissions.where((p) => p.startsWith(group.prefix)))
                        _permTile(p, cs),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save role'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permTile(String p, ColorScheme cs) {
    final checked = _perms[p] == true;
    final dangerous = kDangerousPermissions.contains(p);
    final warn = dangerous && checked;
    final label = p.contains('.') ? p.split('.')[1] : p;
    return CheckboxListTile(
      value: checked,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      activeColor: warn ? _amber : null,
      tileColor: warn ? _amber.withValues(alpha: 0.10) : null,
      title: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: warn ? _amber : null),
            ),
          ),
          if (dangerous) ...[
            const SizedBox(width: 6),
            Icon(Icons.warning_amber_rounded, size: 15, color: _amber),
          ],
        ],
      ),
      onChanged: (v) => setState(() => _perms[p] = v ?? false),
    );
  }
}
