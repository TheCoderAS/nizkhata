// Joining a workspace someone invited you to.
//
// An admin's invite is a document `invites/${workspaceId}_${email}` (see
// Mutations.createInvite). The invited person cannot read the workspace
// until they are a member, so the invite carries the workspace's name and the
// inviter's name for the invitation card. Joining writes the person's own
// membership with the invited role and marks the invite accepted, in one
// batch: the rules allow that membership only while a pending invite for
// that very role exists. Declining marks it declined.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WorkspaceInvite {
  final String id;
  final String workspaceId;
  final String email;
  final String roleId;
  final String? workspaceName;
  final String? invitedByName;
  final String? roleName;
  final DateTime? expiresAt;

  WorkspaceInvite({
    required this.id,
    required this.workspaceId,
    required this.email,
    required this.roleId,
    this.workspaceName,
    this.invitedByName,
    this.roleName,
    this.expiresAt,
  });

  factory WorkspaceInvite.fromMap(String id, Map<String, dynamic> m) {
    final exp = m['expiresAt'];
    return WorkspaceInvite(
      id: id,
      workspaceId: (m['workspaceId'] as String?) ?? '',
      email: (m['email'] as String?) ?? '',
      roleId: (m['roleId'] as String?) ?? '',
      workspaceName: _text(m['workspaceName']),
      invitedByName: _text(m['invitedByName']),
      roleName: _text(m['roleName']),
      expiresAt: exp is Timestamp ? exp.toDate() : (exp is DateTime ? exp : null),
    );
  }

  bool expiredAt(DateTime now) => expiresAt != null && expiresAt!.isBefore(now);

  /// "Home" from Asha, or "a workspace" for an invite made before names were stored.
  String get title => workspaceName ?? 'A workspace';
}

String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

/// Pending, unexpired invites, newest knowledge first, from raw invite maps.
List<WorkspaceInvite> pendingInvites(
  Iterable<({String id, Map<String, dynamic> data})> docs, {
  required Set<String> memberOf,
  required DateTime now,
}) {
  final out = <WorkspaceInvite>[];
  for (final d in docs) {
    if (d.data['status'] != 'pending') continue;
    final inv = WorkspaceInvite.fromMap(d.id, d.data);
    if (inv.workspaceId.isEmpty || inv.roleId.isEmpty) continue;
    if (inv.expiredAt(now)) continue;
    // Already in it (joined on another phone, or added another way).
    if (memberOf.contains(inv.workspaceId)) continue;
    out.add(inv);
  }
  out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return out;
}

class WorkspaceInvites {
  WorkspaceInvites([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  /// The signed-in person's pending invites. The rules let them read only
  /// invites addressed to their own email, so the query must say so.
  Stream<List<({String id, Map<String, dynamic> data})>> watch(String email) {
    final e = email.trim().toLowerCase();
    if (e.isEmpty) return Stream.value(const []);
    return _db
        .collection('invites')
        .where('email', isEqualTo: e)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => [for (final d in s.docs) (id: d.id, data: d.data())]);
  }

  /// Become a member with the invited role, and mark the invite accepted.
  Future<void> accept(WorkspaceInvite inv, User user) async {
    final email = (user.email ?? '').toLowerCase();
    if (email.isEmpty || email != inv.email.toLowerCase()) {
      throw StateError('This invite is for ${inv.email}. Sign in with that Google account to join.');
    }
    final membershipId = '${inv.workspaceId}_${user.uid}';
    final batch = _db.batch();
    batch.set(_db.collection('memberships').doc(membershipId), {
      'id': membershipId,
      'workspaceId': inv.workspaceId,
      'uid': user.uid,
      'roleId': inv.roleId,
      'status': 'active',
      'joinedAt': FieldValue.serverTimestamp(),
      'email': email,
      'displayName': user.displayName,
    });
    batch.update(_db.collection('invites').doc(inv.id), {'status': 'accepted'});
    await batch.commit();
  }

  Future<void> decline(WorkspaceInvite inv) async {
    await _db.collection('invites').doc(inv.id).update({'status': 'declined'});
  }
}
