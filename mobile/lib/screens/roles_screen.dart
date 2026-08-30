// Settings › Roles — ports src/pages/Roles.tsx. Lists workspace roles as cards
// (system-first, then alphabetical), with duplicate/edit/delete for managers.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../data/permissions.dart';
import '../state/auth_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import '../widgets/row_actions.dart';
import 'role_form.dart';

class RolesScreen extends StatelessWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final manage = ws.can('roles.manage');

    final roles = ws.rolesById.values.toList()
      ..sort((a, b) {
        if (a.isSystem != b.isSystem) return a.isSystem ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles'),
        actions: [
          if (manage)
            TextButton.icon(
              onPressed: () => showRoleEditor(context),
              icon: const Icon(Icons.add),
              label: const Text('New role'),
            ),
        ],
      ),
      body: roles.isEmpty
          ? const EmptyView(title: 'No roles')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: roles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) =>
                  _RoleCard(role: roles[i], manage: manage),
            ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final Role role;
  final bool manage;
  const _RoleCard({required this.role, required this.manage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ws = context.watch<WorkspaceController>();
    final granted = kPermissions.where((p) => role.permissions[p] == true).length;
    final memberCount = ws.workspaceMembers.where((m) => m.roleId == role.id).length;

    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          role.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (role.permissions['scope.own'] == true) ...[
                        const SizedBox(width: 8),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          avatar: Icon(Icons.person_pin_circle_outlined, size: 14, color: cs.primary),
                          label: const Text('Own records only'),
                        ),
                      ],
                      if (role.isSystem) ...[
                        const SizedBox(width: 8),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          avatar: Icon(Icons.lock, size: 14, color: cs.onSurfaceVariant),
                          label: const Text('System'),
                          labelStyle: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          side: BorderSide(color: cs.outlineVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$granted / ${kPermissions.length} permissions · $memberCount member(s)',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );

    if (!manage) return card;
    // Long-press for actions (was the 3-dot menu). No swipe: roles are a
    // rarely-touched admin list, and none of these is a daily action.
    return RowActions(
      id: role.id,
      title: role.name,
      menu: [
        RowAction(
            icon: Icons.copy_outlined,
            label: 'Duplicate',
            onTap: () => _duplicate(context)),
        if (!role.isSystem)
          RowAction(
              icon: Icons.edit_outlined,
              label: 'Edit',
              onTap: () => showRoleEditor(context, existing: role)),
        if (!role.isSystem)
          RowAction(
              icon: Icons.delete_outline,
              label: 'Delete',
              destructive: true,
              onTap: () => _confirmDelete(context)),
      ],
      child: card,
    );
  }

  Future<void> _duplicate(BuildContext context) async {
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    final user = context.read<AuthController>().user;
    if (ws == null || user == null) return;
    try {
      await Mutations(Actor.fromUser(user)).duplicateRole(ws, role);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Role duplicated')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Duplicate failed: $e')));
      }
    }
  }

  void _confirmDelete(BuildContext context) {
    final memberships = context.read<WorkspaceController>().workspaceMembers;
    final user = context.read<AuthController>().user;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${role.name}"?'),
        content: const Text('This removes the role.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              if (user == null) return;
              try {
                await Mutations(Actor.fromUser(user)).deleteRole(role, memberships);
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Role deleted')));
                }
              } on GuardrailException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
