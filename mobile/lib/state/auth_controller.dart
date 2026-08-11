// Auth + first-login onboarding — native ports of src/auth/AuthProvider.tsx and
// src/workspace/onboarding.ts. Uses native google_sign_in + firebase_auth
// (no popup/redirect).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';
import '../data/permissions.dart';

class AuthController extends ChangeNotifier {
  AuthController() {
    _auth.authStateChanges().listen(_onAuthChanged);
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final GoogleSignIn _google = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: DefaultFirebaseOptions.googleWebClientId.isEmpty
        ? null
        : DefaultFirebaseOptions.googleWebClientId,
  );

  User? user;
  bool loading = true;
  String? error;
  String? _ensuredUid;

  void _onAuthChanged(User? u) {
    error = null;
    user = u;
    loading = false;
    notifyListeners();
    // Onboarding runs in the background (idempotent, only meaningful first login).
    if (u != null && _ensuredUid != u.uid) {
      _ensuredUid = u.uid;
      _ensureOnboarding(u).catchError((Object e) {
        _ensuredUid = null;
        error = e.toString();
        notifyListeners();
      });
    } else if (u == null) {
      _ensuredUid = null;
    }
  }

  Future<void> signIn() async {
    error = null;
    notifyListeners();
    try {
      final account = await _google.signIn();
      if (account == null) return; // cancelled
      final gAuth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: gAuth.idToken,
        accessToken: gAuth.accessToken,
      );
      await _auth.signInWithCredential(credential);
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  // ---- onboarding (onboarding.ts) ----

  Future<void> _ensureOnboarding(User u) async {
    await _upsertUser(u);
    // Best-effort: claim any pending cross-user share invites (forms the
    // SharedConnection so the Shared ledger works). Ports claimShareInvites.
    try {
      await _claimShareInvites(u);
    } catch (_) {/* non-critical — never block sign-in */}
    var workspaceIds = await _listMembershipWorkspaceIds(u.uid);
    if (workspaceIds.isEmpty) {
      final id = await createPersonalWorkspace(u);
      workspaceIds = [id];
    }
    final userRef = _db.collection('users').doc(u.uid);
    final snap = await userRef.get();
    final last = snap.data()?['lastWorkspaceId'];
    if ((last == null || last == '') && workspaceIds.isNotEmpty) {
      await userRef.set({'lastWorkspaceId': workspaceIds.first}, SetOptions(merge: true));
    }
  }

  Future<void> _upsertUser(User u) async {
    final ref = _db.collection('users').doc(u.uid);
    final email = (u.email ?? '').toLowerCase();
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'uid': u.uid,
        'email': email,
        'displayName': u.displayName,
        'photoURL': u.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'lastWorkspaceId': null,
      });
    } else {
      await ref.set({
        'email': email,
        'displayName': u.displayName,
        'photoURL': u.photoURL,
      }, SetOptions(merge: true));
    }
  }

  /// Claim pending share invites addressed to this user's email: establish the
  /// SharedConnection (denormalized names/emails) and mark each invite accepted.
  /// Ports src/workspace/onboarding.ts claimShareInvites.
  Future<void> _claimShareInvites(User u) async {
    final email = (u.email ?? '').toLowerCase();
    if (email.isEmpty) return;
    final snap = await _db
        .collection('shareInvites')
        .where('toEmail', isEqualTo: email)
        .where('status', isEqualTo: 'pending')
        .get();
    final meName = (u.displayName?.trim().isNotEmpty ?? false)
        ? u.displayName!.trim()
        : (email.isNotEmpty ? email : (u.uid.length >= 8 ? '${u.uid.substring(0, 8)}…' : u.uid));
    for (final doc in snap.docs) {
      final inv = doc.data();
      final expiresAt = inv['expiresAt'];
      if (expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now())) continue;
      final fromUid = inv['fromUid'] as String? ?? '';
      if (fromUid.isEmpty) continue;
      final pair = [fromUid, u.uid]..sort();
      final connId = pair.join('_');
      final batch = _db.batch();
      batch.set(_db.collection('sharedConnections').doc(connId), {
        'id': connId,
        'uids': pair,
        'names': {fromUid: inv['fromName'] ?? '', u.uid: meName},
        'emails': {fromUid: inv['fromEmail'] ?? '', u.uid: email},
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(_db.collection('shareInvites').doc(doc.id), {'status': 'accepted'},
          SetOptions(merge: true));
      await batch.commit();
    }
  }

  Future<List<String>> _listMembershipWorkspaceIds(String uid) async {
    final snap = await _db.collection('memberships').where('uid', isEqualTo: uid).get();
    return snap.docs.map((d) => (d.data()['workspaceId'] as String?) ?? '').where((s) => s.isNotEmpty).toList();
  }

  Future<String> createPersonalWorkspace(User u, {String? name}) async {
    final wsRef = _db.collection('workspaces').doc();
    final workspaceId = wsRef.id;
    final wsName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (u.displayName != null && u.displayName!.isNotEmpty
            ? "${u.displayName!.split(' ').first}'s Workspace"
            : 'My Workspace');
    await wsRef.set({
      'id': workspaceId,
      'name': wsName,
      'ownerId': u.uid,
      'baseCurrency': 'INR',
      'fyStartMonth': 4,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final batch = _db.batch();
    var ownerRoleId = '';
    final templates = systemRoleTemplates();
    for (final roleName in kSystemRoleOrder) {
      final roleRef = _db.collection('roles').doc();
      if (roleName == 'Owner') ownerRoleId = roleRef.id;
      batch.set(roleRef, {
        'id': roleRef.id,
        'workspaceId': workspaceId,
        'name': roleName,
        'isSystem': true,
        'permissions': templates[roleName],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    final membershipId = '${workspaceId}_${u.uid}';
    batch.set(_db.collection('memberships').doc(membershipId), {
      'id': membershipId,
      'workspaceId': workspaceId,
      'uid': u.uid,
      'roleId': ownerRoleId,
      'status': 'active',
      'joinedAt': FieldValue.serverTimestamp(),
      'email': (u.email ?? '').toLowerCase(),
      'displayName': u.displayName,
    });
    for (final cat in kDefaultCategories) {
      final catRef = _db.collection('categories').doc();
      batch.set(catRef, {
        'id': catRef.id,
        'workspaceId': workspaceId,
        'name': cat.name,
        'kind': cat.kind,
        'isSystem': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return workspaceId;
  }
}
