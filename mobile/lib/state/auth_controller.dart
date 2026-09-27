// Auth + first-login onboarding — native ports of src/auth/AuthProvider.tsx and
// src/workspace/onboarding.ts. Uses native google_sign_in + firebase_auth
// (no popup/redirect).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/currency.dart';
import '../firebase_options.dart';
import '../data/permissions.dart';

/// The fields a new workspace document starts with, less the server
/// timestamp. Kept apart from the Firestore write so the one thing that can
/// never be undone, the currency, can be checked without Firebase.
///
/// The currency is permanent once written, so an unknown code is refused here
/// rather than stored. The financial year only starts from the currency's
/// usual month; unlike the currency, the workspace can change it later.
Map<String, dynamic> newWorkspaceFields({
  required String id,
  required String name,
  required String ownerId,
  required String currency,
}) {
  final code = currency.trim().toUpperCase();
  if (!kCurrencies.any((c) => c.code == code)) {
    throw ArgumentError.value(currency, 'currency', 'not a currency the app offers');
  }
  return {
    'id': id,
    'name': name,
    'ownerId': ownerId,
    'baseCurrency': code,
    'fyStartMonth': currencySpec(code).defaultFyStartMonth,
  };
}

/// What a workspace is called when the person has not named it.
String defaultWorkspaceName(String? displayName) {
  final first = (displayName ?? '').trim().split(' ').first;
  return first.isEmpty ? 'My Workspace' : "$first's Workspace";
}

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

  /// Signed in, but a member of no workspace at all: a first sign-in. The
  /// workspace is not made for them, because its currency is permanent and
  /// only they can say which one they keep their money in. The router sends
  /// them to the choose-currency screen until [createFirstWorkspace] runs.
  bool needsWorkspace = false;

  void _onAuthChanged(User? u) {
    error = null;
    if (u?.uid != user?.uid) needsWorkspace = false;
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
    final workspaceIds = await _listMembershipWorkspaceIds(u.uid);
    if (workspaceIds.isEmpty) {
      // Wait for the person to choose the currency. The screen that asks
      // calls createFirstWorkspace, which records lastWorkspaceId itself.
      if (user?.uid == u.uid) {
        needsWorkspace = true;
        notifyListeners();
      }
      return;
    }
    final userRef = _db.collection('users').doc(u.uid);
    final snap = await userRef.get();
    final last = snap.data()?['lastWorkspaceId'];
    if (last == null || last == '') {
      await userRef.set({'lastWorkspaceId': workspaceIds.first}, SetOptions(merge: true));
    }
  }

  /// Make the first workspace of someone who has none, in the currency they
  /// chose, and let the router carry them on into the app.
  Future<void> createFirstWorkspace(String currency) async {
    final u = user;
    if (u == null) return;
    final id = await createPersonalWorkspace(u, currency: currency);
    // The workspace exists now, so nothing after this may send them back to
    // make another. The app picks its active workspace without lastWorkspaceId,
    // so losing that write costs nothing; a retried creation would cost a
    // duplicate workspace.
    needsWorkspace = false;
    notifyListeners();
    try {
      await _db.collection('users').doc(u.uid).set({'lastWorkspaceId': id}, SetOptions(merge: true));
    } catch (_) {}
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
      batch.set(_db.collection('shareInvites').doc(doc.id), {'status': 'accepted'}, SetOptions(merge: true));
      await batch.commit();
    }
  }

  Future<List<String>> _listMembershipWorkspaceIds(String uid) async {
    final snap = await _db.collection('memberships').where('uid', isEqualTo: uid).get();
    // Offline on a fresh install, the query answers from an empty cache. That
    // is no proof of having no workspace, and taking it as proof would ask an
    // existing member to start a new one. Fail instead; the next sign-in or
    // launch checks again.
    if (snap.docs.isEmpty && snap.metadata.isFromCache) {
      throw StateError("Couldn't reach NizKhata to load your workspaces. Check your connection.");
    }
    return snap.docs
        .map((d) => (d.data()['workspaceId'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Create a workspace owned by [u] that keeps its books in [currency].
  ///
  /// The currency is required, with no default, because it can never be
  /// changed afterwards: every caller must have asked the person.
  Future<String> createPersonalWorkspace(User u, {String? name, required String currency}) async {
    final wsRef = _db.collection('workspaces').doc();
    final workspaceId = wsRef.id;
    final wsName =
        (name != null && name.trim().isNotEmpty) ? name.trim() : defaultWorkspaceName(u.displayName);
    // Built before any write, so a bad code fails with nothing half made.
    final fields = newWorkspaceFields(id: workspaceId, name: wsName, ownerId: u.uid, currency: currency);
    await wsRef.set({...fields, 'createdAt': FieldValue.serverTimestamp()});

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
