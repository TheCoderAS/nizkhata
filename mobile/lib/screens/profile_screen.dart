// Settings › Account — ports src/pages/Account.tsx. The signed-in user's
// personal profile plus the workspaces they belong to (with a "Leave" action).
// Profile fields come from the Google identity (read-only).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/currency.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../services/app_lock.dart';
import '../state/auth_controller.dart';
import '../state/theme_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import '../widgets/currency_picker.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final ws = context.watch<WorkspaceController>();
    final user = auth.user;
    final uid = user?.uid ?? '';
    final cs = Theme.of(context).colorScheme;

    final myWorkspaces = [...ws.workspaces]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Profile',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                      child: user?.photoURL == null
                          ? Text(initialsOf(user?.displayName ?? user?.email ?? '?'))
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.displayName ?? '—',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          if (user?.email != null)
                            Text(user!.email!, style: TextStyle(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Your name, email and photo come from your Google account.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Workspaces',
            child: Column(
              children: [
                if (myWorkspaces.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No workspaces.', style: TextStyle(color: cs.onSurfaceVariant)),
                  )
                else
                  for (final w in myWorkspaces) _workspaceTile(context, ws, w, uid),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add),
                  title: const Text('Create workspace'),
                  onTap: () => _createWorkspace(context, auth, ws),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Appearance',
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
              ],
              selected: {context.watch<ThemeController>().mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => context.read<ThemeController>().setMode(s.first),
            ),
          ),
          const SizedBox(height: 16),
          const SectionCard(
            title: 'Security',
            child: _AppLockTile(),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Session',
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  await auth.signOut();
                  if (context.mounted) context.go('/login');
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createWorkspace(BuildContext context, AuthController auth, WorkspaceController ws) async {
    final user = auth.user;
    if (user == null) return;
    final request = await showDialog<NewWorkspaceRequest>(
      context: context,
      useRootNavigator: true,
      // A second workspace is usually kept in the same country as the first,
      // so start from the currency in use now. Still only a preselection.
      builder: (_) => NewWorkspaceDialog(initialCurrency: ws.currency),
    );
    if (request == null) return;
    final name = request.name;
    try {
      final id = await auth.createPersonalWorkspace(user, name: name, currency: request.currency);
      await ws.switchWorkspace(id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Created "$name"')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't create workspace: $e")));
      }
    }
  }

  Widget _workspaceTile(BuildContext context, WorkspaceController ws, Workspace w, String uid) {
    final isOwner = w.ownerId == uid;
    final isActive = w.id == ws.activeWorkspaceId;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Flexible(child: Text(w.name, overflow: TextOverflow.ellipsis)),
          if (isActive) ...[
            const SizedBox(width: 8),
            const Chip(
              label: Text('Active'),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
      trailing: isOwner
          ? const Chip(
              label: Text('Owner'),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            )
          : TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () => _confirmLeave(context, ws, w),
              icon: const Icon(Icons.meeting_room_outlined, size: 18),
              label: const Text('Leave'),
            ),
      onTap: isActive ? null : () => ws.switchWorkspace(w.id),
    );
  }

  void _confirmLeave(BuildContext context, WorkspaceController ws, Workspace w) {
    final user = context.read<AuthController>().user;
    if (user == null) return;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text('Leave "${w.name}"?'),
        content: const Text("You'll lose access to this workspace. An admin can re-invite you later."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              Membership? membership;
              for (final m in ws.memberships) {
                if (m.workspaceId == w.id) {
                  membership = m;
                  break;
                }
              }
              if (membership == null) return;
              try {
                await Mutations(Actor.fromUser(user)).leaveWorkspace(membership, w.ownerId);
                // If we left the active workspace, switch to another.
                if (ws.activeWorkspaceId == w.id) {
                  Membership? next;
                  for (final m in ws.memberships) {
                    if (m.workspaceId != w.id) {
                      next = m;
                      break;
                    }
                  }
                  if (next != null) await ws.switchWorkspace(next.workspaceId);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Left workspace')));
                }
              } on GuardrailException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't leave: $e")));
                }
              }
            },
            child: const Text('Leave workspace'),
          ),
        ],
      ),
    );
  }
}

/// What the new-workspace dialog hands back: a name and the chosen currency.
typedef NewWorkspaceRequest = ({String name, String currency});

/// Name the new workspace and choose its currency. The currency is permanent,
/// so it is asked here in full rather than copied silently from the workspace
/// in use.
class NewWorkspaceDialog extends StatefulWidget {
  final String initialCurrency;
  const NewWorkspaceDialog({super.key, required this.initialCurrency});

  @override
  State<NewWorkspaceDialog> createState() => _NewWorkspaceDialogState();
}

class _NewWorkspaceDialogState extends State<NewWorkspaceDialog> {
  final _name = TextEditingController();
  // A workspace made before the catalogue settled could carry a code the app
  // no longer offers; it cannot seed a new one, so start from the rupee.
  late String _currency =
      kCurrencies.any((c) => c.code == widget.initialCurrency) ? widget.initialCurrency : 'INR';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) return;
    Navigator.pop<NewWorkspaceRequest>(context, (name: _name.text.trim(), currency: _currency));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New workspace'),
      // Scrolls so the keyboard on a short phone cannot push the fields into
      // an overflow.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Household'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            const SectionLabel('Currency'),
            CurrencyField(value: _currency, onChanged: (c) => setState(() => _currency = c)),
            const SizedBox(height: 10),
            const CurrencyLockNote(),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _valid ? _submit : null, child: const Text('Create')),
      ],
    );
  }
}

/// App-lock toggle: requires the device to support biometrics or credentials;
/// enabling verifies once so a typo-free setup can't lock the user out.
class _AppLockTile extends StatefulWidget {
  const _AppLockTile();

  @override
  State<_AppLockTile> createState() => _AppLockTileState();
}

class _AppLockTileState extends State<_AppLockTile> {
  bool _enabled = false;
  bool _supported = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    () async {
      final enabled = await AppLock.isEnabled();
      final supported = await AppLock.isSupported();
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _supported = supported;
          _loading = false;
        });
      }
    }();
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      // Prove it works before turning it on.
      final ok = await AppLock.authenticate();
      if (!ok) return;
    }
    await AppLock.setEnabled(value);
    if (mounted) setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.fingerprint),
      title: const Text('App lock'),
      subtitle: Text(_supported
          ? 'Require fingerprint or device PIN when opening the app'
          : 'Set up a screen lock on this device first'),
      value: _enabled,
      onChanged: _loading || !_supported ? null : _toggle,
    );
  }
}
