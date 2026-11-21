// Invitations to join someone's workspace: shown on the first-run screen (so
// an invited person can join instead of starting books of their own) and in
// Account > Workspaces. Renders nothing when there are none.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/workspace_invites.dart';
import 'common.dart';

class WorkspaceInvitesCard extends StatefulWidget {
  final User user;

  /// Workspaces the person is already in; their invites are not offered again.
  final Set<String> memberOf;

  /// After joining: switch to it (and, on first run, leave the welcome screen).
  final Future<void> Function(String workspaceId) onJoined;

  /// Wrap the list in a card with a heading (Account) or show it bare (welcome).
  final bool asSection;

  const WorkspaceInvitesCard({
    super.key,
    required this.user,
    required this.memberOf,
    required this.onJoined,
    this.asSection = true,
  });

  @override
  State<WorkspaceInvitesCard> createState() => _WorkspaceInvitesCardState();
}

class _WorkspaceInvitesCardState extends State<WorkspaceInvitesCard> {
  final _invites = WorkspaceInvites();
  late Stream<List<({String id, Map<String, dynamic> data})>> _stream = _invites.watch(widget.user.email ?? '');
  String? _busyId;

  @override
  void didUpdateWidget(WorkspaceInvitesCard old) {
    super.didUpdateWidget(old);
    if (old.user.email != widget.user.email) _stream = _invites.watch(widget.user.email ?? '');
  }

  Future<void> _answer(WorkspaceInvite inv, bool join) async {
    setState(() => _busyId = inv.id);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (join) {
        await _invites.accept(inv, widget.user);
        await widget.onJoined(inv.workspaceId);
        messenger?.showSnackBar(SnackBar(content: Text('You joined ${inv.title}')));
      } else {
        await _invites.decline(inv);
        messenger?.showSnackBar(const SnackBar(content: Text('Invitation declined')));
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(
        content: Text(e is StateError
            ? e.message
            : (join
                ? "Couldn't join. The invite may have been withdrawn or changed; ask for a new one."
                : "Couldn't decline. Check your connection and try again.")),
      ));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _confirmJoin(WorkspaceInvite inv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Join ${inv.title}?'),
        content: Text(
          '${inv.invitedByName ?? 'Someone'} invited you'
          '${inv.roleName != null ? ' as ${inv.roleName}' : ''}. '
          'You will see this workspace\'s books and can work in them as that role allows. '
          'You can leave it any time from Account.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Join')),
        ],
      ),
    );
    if (ok == true) await _answer(inv, true);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<({String id, Map<String, dynamic> data})>>(
      stream: _stream,
      builder: (context, snap) {
        final list = pendingInvites(snap.data ?? const [], memberOf: widget.memberOf, now: DateTime.now());
        if (list.isEmpty) return const SizedBox.shrink();
        final tiles = [
          for (final inv in list)
            ListTile(
              key: Key('invite-${inv.id}'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mail_outline),
              title: Text(inv.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_from(inv)),
              trailing: _busyId == inv.id
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: _busyId != null ? null : () => _answer(inv, false),
                          child: const Text('Decline'),
                        ),
                        FilledButton(
                          onPressed: _busyId != null ? null : () => _confirmJoin(inv),
                          child: const Text('Join'),
                        ),
                      ],
                    ),
            ),
        ];
        final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: tiles);
        if (!widget.asSection) return body;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SectionCard(
            title: list.length == 1 ? 'Invitation' : 'Invitations',
            icon: Icons.mail_outline,
            child: body,
          ),
        );
      },
    );
  }
}

/// "From Asha as Editor", or a plain line for an invite without names.
String _from(WorkspaceInvite inv) {
  final parts = [
    if (inv.invitedByName != null) 'From ${inv.invitedByName}',
    if (inv.roleName != null) 'as ${inv.roleName}',
  ];
  return parts.isEmpty ? 'You are invited to join' : parts.join(' ');
}
