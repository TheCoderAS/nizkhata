// Settings › Members — ports src/pages/Members.tsx. Lists members + roles,
// invite, change role, remove (owner protected), and pending invites. Reads
// memberships/roles from WorkspaceController; invites via a live Firestore
// StreamBuilder. Admin writes go through Mutations (createInvite, revokeInvite,
// changeMemberRole, removeMember) and surface GuardrailException messages.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

/// Best display label for a member: denormalized name, then email, then a short
/// uid fallback (older memberships created before identity was stored).
String _memberLabel(Membership m) =>
    m.displayName ?? m.email ?? '${m.uid.substring(0, m.uid.length < 8 ? m.uid.length : 8)}…';

/// The reserved Owner role — the seeded system role named "Owner", never
/// assignable to anyone but the workspace owner.
bool _isOwnerRole(Role r) => r.isSystem && r.name == 'Owner';

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final user = context.read<AuthController>().user;
    final currentUid = user?.uid;
    final ownerId = ws.activeWorkspace?.ownerId;
    final canInvite = ws.can('members.invite');
    final canRemove = ws.can('members.remove');

    final assignableRoles =
        ws.rolesById.values.where((r) => !_isOwnerRole(r)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          if (canInvite)
            IconButton(
              icon: const Icon(Icons.person_add_alt),
              tooltip: 'Invite',
              onPressed: () => _showInviteDialog(context, assignableRoles),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          for (final m in ws.memberships)
            _MemberTile(
              membership: m,
              ownerId: ownerId,
              currentUid: currentUid,
              canInvite: canInvite,
              canRemove: canRemove,
              assignableRoles: assignableRoles,
            ),
          _PendingInvites(canInvite: canInvite),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final Membership membership;
  final String? ownerId;
  final String? currentUid;
  final bool canInvite;
  final bool canRemove;
  final List<Role> assignableRoles;
  const _MemberTile({
    required this.membership,
    required this.ownerId,
    required this.currentUid,
    required this.canInvite,
    required this.canRemove,
    required this.assignableRoles,
  });

  Future<void> _changeRole(BuildContext context, Role newRole) async {
    final user = context.read<AuthController>().user;
    if (user == null || ownerId == null) return;
    try {
      await Mutations(Actor.fromUser(user)).changeMemberRole(membership, newRole, ownerId!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role updated')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final user = context.read<AuthController>().user;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: const Text('They will lose access to this workspace.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              if (user == null || ownerId == null) return;
              try {
                await Mutations(Actor.fromUser(user)).removeMember(membership, ownerId!);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member removed')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final cs = Theme.of(context).colorScheme;
    final isOwner = membership.uid == ownerId;
    final isSelf = membership.uid == currentUid;
    final label = isSelf ? 'You' : _memberLabel(membership);
    final roleName = ws.rolesById[membership.roleId]?.name ?? '—';
    final showEmail = !isSelf && membership.displayName != null && membership.email != null;

    final Widget roleWidget;
    if (canInvite && !isOwner) {
      final hasCurrent = assignableRoles.any((r) => r.id == membership.roleId);
      roleWidget = DropdownButton<String>(
        value: hasCurrent ? membership.roleId : null,
        underline: const SizedBox.shrink(),
        items: [
          for (final r in assignableRoles) DropdownMenuItem(value: r.id, child: Text(r.name)),
        ],
        onChanged: (v) {
          if (v == null) return;
          final role = ws.rolesById[v];
          if (role != null) _changeRole(context, role);
        },
      );
    } else {
      roleWidget = Text(
        roleName,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
      );
    }

    return ListTile(
      leading: EntityAvatar(name: isSelf ? _memberLabel(membership) : label),
      title: Row(
        children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          if (isOwner) ...[
            const SizedBox(width: 8),
            _Chip(text: 'Owner'),
          ],
        ],
      ),
      subtitle: showEmail ? Text(membership.email!) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          roleWidget,
          if (canRemove && !isOwner)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove member',
              onPressed: () => _confirmRemove(context),
            ),
        ],
      ),
    );
  }
}

class _PendingInvites extends StatelessWidget {
  final bool canInvite;
  const _PendingInvites({required this.canInvite});

  Future<void> _revoke(BuildContext context, String id) async {
    final user = context.read<AuthController>().user;
    if (user == null) return;
    try {
      await Mutations(Actor.fromUser(user)).revokeInvite(id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite revoked')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final wsId = ws.activeWorkspaceId;
    if (wsId == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('invites')
          .where('workspaceId', isEqualTo: wsId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 4),
              child: Text(
                'PENDING INVITES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            for (final doc in docs)
              Builder(builder: (context) {
                final data = doc.data() as Map<String, dynamic>;
                final email = (data['email'] ?? '') as String;
                final roleName = ws.rolesById[data['roleId']]?.name ?? '—';
                return ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(email),
                  subtitle: Text(roleName),
                  trailing: canInvite
                      ? IconButton(
                          icon: const Icon(Icons.block),
                          tooltip: 'Revoke invite',
                          onPressed: () => _revoke(context, doc.id),
                        )
                      : null,
                );
              }),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
    );
  }
}

// ---- invite dialog ----

final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

void _showInviteDialog(BuildContext context, List<Role> roles) {
  showDialog<void>(
    context: context,
    builder: (_) => _InviteDialog(roles: roles),
  );
}

class _InviteDialog extends StatefulWidget {
  final List<Role> roles;
  const _InviteDialog({required this.roles});
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  late String? _roleId = widget.roles.isNotEmpty ? widget.roles.first.id : null;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_roleId == null) return;
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    final user = context.read<AuthController>().user;
    if (ws == null || user == null) return;
    setState(() => _busy = true);
    try {
      await Mutations(Actor.fromUser(user)).createInvite(ws, _email.text.trim(), _roleId!, user.uid);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite sent')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite member'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email', hintText: 'person@example.com'),
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Email is required';
                if (!_emailRe.hasMatch(t)) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _roleId,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                for (final r in widget.roles) DropdownMenuItem(value: r.id, child: Text(r.name)),
              ],
              onChanged: (v) => setState(() => _roleId = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send invite'),
        ),
      ],
    );
  }
}
