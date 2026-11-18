// Deleting an account, and everything in it.
//
// Google Play requires that someone who signs up can also leave, taking their
// data with them. There is no server here, so the phone does the deleting,
// and the Firestore rules decide what it may delete at each step. That makes
// the ORDER the whole design:
//
//   1. Everyday records (transactions, dues, accounts, ...) go first. Their
//      rules check the person's role, so the workspace and its roles must
//      still exist while they are removed.
//   2. Other people's memberships go next. That rule reads the workspace
//      document to know who the owner is.
//   3. The workspace document itself.
//   4. What nobody may delete while a workspace exists: its audit log, its
//      built-in categories, and its roles. The rules allow these only once
//      the workspace document is gone, and only to someone still a member.
//      Roles go last, after the categories, so nothing after them needs one.
//   5. The person's own membership.
//
// A workspace someone only belongs to (owned by another person) is not
// theirs to delete: they leave it, and its records stay with its owner.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Records removed while the workspace and its roles still exist. Their
/// rules check the deleting person's permissions.
const kErasedWithWorkspaceAlive = [
  'transactions',
  'dues',
  'debts',
  'budgets',
  'contacts',
  'accounts',
  'invites',
];

/// Records removed only after the workspace document is gone. Order matters:
/// roles last, since the category rule still tries the role-based branch.
const kErasedAfterWorkspace = ['revisions', 'categories', 'roles'];

/// What was removed, for the confirmation the person sees.
class ErasureReport {
  int workspacesDeleted = 0;
  int workspacesLeft = 0;
  int documentsDeleted = 0;
}

class AccountEraser {
  AccountEraser([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  /// Firestore takes at most 500 writes in one batch; stay well under.
  static const _chunk = 400;

  /// Every read comes from the server. Offline, the cache can be missing
  /// records, and deleting only what the cache knows would leave the rest
  /// behind; failing outright is the honest answer.
  static const _server = GetOptions(source: Source.server);

  /// Delete every document [uid] owns, leave every workspace they only belong
  /// to, and remove their profile. Does not touch Firebase Auth: the caller
  /// deletes the sign-in itself once this has succeeded, so a failure here
  /// never leaves data behind an account that no longer exists.
  Future<ErasureReport> eraseAccount(String uid) async {
    final report = ErasureReport();

    final memberships = await _db.collection('memberships').where('uid', isEqualTo: uid).get(_server);
    for (final m in memberships.docs) {
      final wsId = m.data()['workspaceId'] as String?;
      if (wsId == null || wsId.isEmpty) continue;
      final ws = await _db.collection('workspaces').doc(wsId).get(_server);
      if (ws.exists && ws.data()?['ownerId'] == uid) {
        report.documentsDeleted += await eraseWorkspace(wsId, uid);
        report.workspacesDeleted++;
      } else if (!ws.exists) {
        // Already gone: a deletion that stopped part way. Finish clearing it.
        report.documentsDeleted += await _eraseLeftovers(wsId);
        await m.reference.delete();
      } else {
        // Someone else's workspace: just leave it.
        await m.reference.delete();
        report.workspacesLeft++;
      }
    }

    report.documentsDeleted += await _eraseShared(uid);
    await _db.collection('users').doc(uid).delete();
    report.documentsDeleted++;
    return report;
  }

  /// Delete workspace [wsId], owned by [ownerUid], and every record in it.
  /// Returns how many documents were removed.
  Future<int> eraseWorkspace(String wsId, String ownerUid) async {
    var n = 0;
    for (final col in kErasedWithWorkspaceAlive) {
      n += await _deleteWhere(_db.collection(col).where('workspaceId', isEqualTo: wsId));
    }

    final members = await _db.collection('memberships').where('workspaceId', isEqualTo: wsId).get(_server);
    n += await _deleteDocs(members.docs.where((d) => d.data()['uid'] != ownerUid).map((d) => d.reference));

    await _db.collection('workspaces').doc(wsId).delete();
    n++;

    for (final col in kErasedAfterWorkspace) {
      n += await _deleteWhere(_db.collection(col).where('workspaceId', isEqualTo: wsId));
    }

    await _db.collection('memberships').doc('${wsId}_$ownerUid').delete();
    n++;

    try {
      final userRef = _db.collection('users').doc(ownerUid);
      final snap = await userRef.get();
      if (snap.data()?['lastWorkspaceId'] == wsId) {
        await userRef.update({'lastWorkspaceId': null});
      }
    } catch (_) {}
    return n;
  }

  /// What remains of a workspace whose document is already deleted, when an
  /// earlier deletion stopped part way. Each step is tried on its own: what
  /// the rules still allow is removed, and the rest is reported by the caller
  /// running this again, not hidden.
  Future<int> _eraseLeftovers(String wsId) async {
    var n = 0;
    for (final col in [...kErasedWithWorkspaceAlive, ...kErasedAfterWorkspace]) {
      try {
        n += await _deleteWhere(_db.collection(col).where('workspaceId', isEqualTo: wsId));
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
    }
    return n;
  }

  /// The shared ledger: entries this person created, their connections, and
  /// invites they sent. Entries someone ELSE created belong to that person's
  /// records and stay with them.
  Future<int> _eraseShared(String uid) async {
    var n = 0;
    final entries = await _db.collection('sharedEntries').where('uids', arrayContains: uid).get(_server);
    n += await _deleteDocs(entries.docs.where((d) => d.data()['creatorUid'] == uid).map((d) => d.reference));
    n += await _deleteWhere(_db.collection('sharedConnections').where('uids', arrayContains: uid));
    n += await _deleteWhere(_db.collection('shareInvites').where('fromUid', isEqualTo: uid));
    return n;
  }

  Future<int> _deleteWhere(Query<Map<String, dynamic>> query) async {
    final snap = await query.get(_server);
    return _deleteDocs(snap.docs.map((d) => d.reference));
  }

  Future<int> _deleteDocs(Iterable<DocumentReference> refs) async {
    final all = refs.toList();
    for (var i = 0; i < all.length; i += _chunk) {
      final batch = _db.batch();
      for (final r in all.skip(i).take(_chunk)) {
        batch.delete(r);
      }
      await batch.commit();
    }
    return all.length;
  }
}
