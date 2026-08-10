// Settings › Workspace — ports src/pages/WorkspaceSettings.tsx. Name, currency,
// FY start month; delete (owner only).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

const _kCurrencies = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD', 'AUD', 'CAD'];
const _kMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

class WorkspaceSettingsScreen extends StatefulWidget {
  const WorkspaceSettingsScreen({super.key});

  @override
  State<WorkspaceSettingsScreen> createState() => _WorkspaceSettingsScreenState();
}

class _WorkspaceSettingsScreenState extends State<WorkspaceSettingsScreen> {
  final _name = TextEditingController();
  String _currency = 'INR';
  int _fyStartMonth = 4;
  bool _busy = false;
  bool _seeded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _seed(ws) {
    final w = ws.activeWorkspace;
    if (w == null || _seeded) return;
    _name.text = w.name;
    _currency = _kCurrencies.contains(w.baseCurrency) ? w.baseCurrency : 'INR';
    _fyStartMonth = (w.fyStartMonth >= 1 && w.fyStartMonth <= 12) ? w.fyStartMonth : 4;
    _seeded = true;
  }

  Future<void> _save() async {
    final ws = context.read<WorkspaceController>();
    final user = context.read<AuthController>().user;
    final w = ws.activeWorkspace;
    if (w == null || user == null) return;
    setState(() => _busy = true);
    try {
      await Mutations(Actor.fromUser(user)).updateWorkspace(
        w.id,
        name: _name.text.trim(),
        baseCurrency: _currency,
        fyStartMonth: _fyStartMonth,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Workspace updated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirmDelete() {
    final ws = context.read<WorkspaceController>();
    final auth = context.read<AuthController>();
    final user = auth.user;
    final w = ws.activeWorkspace;
    if (w == null || user == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${w.name}"?'),
        content: const Text(
            'This permanently removes the workspace for everyone — all members lose access. '
            'Transaction, account and role documents are not auto-deleted by the client.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              final deletedId = w.id;
              try {
                await Mutations(Actor.fromUser(user)).deleteWorkspace(deletedId, user.uid);
                if (!mounted) return;
                // Move to another workspace if one exists; otherwise sign out.
                Membership? next;
                for (final m in ws.memberships) {
                  if (m.workspaceId != deletedId) {
                    next = m;
                    break;
                  }
                }
                if (next != null) {
                  await ws.switchWorkspace(next.workspaceId);
                  if (mounted) context.go('/dashboard');
                } else {
                  await auth.signOut();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                }
              }
            },
            child: const Text('Delete workspace'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final w = ws.activeWorkspace;

    if (w == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workspace')),
        body: const LoadingView(),
      );
    }
    _seed(ws);

    final user = context.read<AuthController>().user;
    final isOwner = user != null && user.uid == w.ownerId;
    final canDelete = isOwner && ws.can('workspace.delete');

    return Scaffold(
      appBar: AppBar(title: const Text('Workspace')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'General',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _currency,
                  decoration: const InputDecoration(labelText: 'Base currency'),
                  items: [
                    for (final c in _kCurrencies) DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() => _currency = v ?? 'INR'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _fyStartMonth,
                  decoration: const InputDecoration(labelText: 'FY start month'),
                  items: [
                    for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text(_kMonths[i - 1])),
                  ],
                  onChanged: (v) => setState(() => _fyStartMonth = v ?? 4),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: (_busy || _name.text.trim().isEmpty) ? null : _save,
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save changes'),
                ),
              ],
            ),
          ),
          if (canDelete) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'Danger zone',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Deleting a workspace removes it for everyone. This cannot be undone.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                    onPressed: _confirmDelete,
                    child: const Text('Delete workspace'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
