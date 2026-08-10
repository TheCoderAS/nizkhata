// Live subscriptions for the cross-user shared ledger — port of
// src/data/SharedDataProvider.tsx. Unlike WorkspaceController/DataController
// these are scoped by the signed-in user's uid, NOT by workspace: the same
// partners/entries are visible no matter which workspace is active. Powers the
// Shared screen and its inbox badge.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/shared_mutations.dart';

class SharedController extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _uid;
  bool loading = true;
  String? error;

  List<SharedConnection> connections = [];
  List<SharedEntry> entries = [];
  // Share invites I sent (pending/accepted/revoked).
  List<ShareInvite> sentInvites = [];

  StreamSubscription<QuerySnapshot>? _connSub;
  StreamSubscription<QuerySnapshot>? _entriesSub;
  StreamSubscription<QuerySnapshot>? _invitesSub;

  /// Entries awaiting MY response (the inbox).
  int get inboxCount {
    final u = _uid;
    if (u == null) return 0;
    return entries.where((e) => e.pendingForUids.contains(u)).length;
  }

  void setUid(String? uid) {
    if (uid == _uid) return;
    _uid = uid;
    _connSub?.cancel();
    _entriesSub?.cancel();
    _invitesSub?.cancel();
    if (uid == null) {
      connections = [];
      entries = [];
      sentInvites = [];
      loading = false;
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();

    _connSub = _db
        .collection('sharedConnections')
        .where('uids', arrayContains: uid)
        .snapshots()
        .listen((snap) {
      connections = snap.docs.map(SharedConnection.fromDoc).toList();
      error = null;
      notifyListeners();
    }, onError: _onErr);

    _entriesSub = _db
        .collection('sharedEntries')
        .where('uids', arrayContains: uid)
        .orderBy('date', descending: true)
        .snapshots()
        .listen((snap) {
      entries = snap.docs.map(SharedEntry.fromDoc).toList();
      error = null;
      loading = false;
      notifyListeners();
    }, onError: (Object e) {
      error = e.toString();
      loading = false;
      notifyListeners();
    });

    _invitesSub = _db
        .collection('shareInvites')
        .where('fromUid', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      sentInvites = snap.docs.map(ShareInvite.fromDoc).toList();
      notifyListeners();
    }, onError: _onErr);
  }

  void _onErr(Object e) {
    error = e.toString();
    notifyListeners();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _entriesSub?.cancel();
    _invitesSub?.cancel();
    super.dispose();
  }
}
