// Workspace context — ports src/workspace/WorkspaceProvider.tsx. Streams the
// user's memberships + roles, resolves an active workspace (persisted), and
// exposes can(permission).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';

class WorkspaceController extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _uid;
  bool loading = true;
  String? error;
  List<Membership> memberships = [];
  List<Workspace> workspaces = [];
  Map<String, Role> rolesById = {};
  String? activeWorkspaceId;

  StreamSubscription<QuerySnapshot>? _memSub;
  StreamSubscription<QuerySnapshot>? _wsSub;
  StreamSubscription<QuerySnapshot>? _rolesSub;
  SharedPreferences? _prefs;

  static const _prefKey = 'activeWorkspaceId';

  Workspace? get activeWorkspace {
    for (final w in workspaces) {
      if (w.id == activeWorkspaceId) return w;
    }
    return null;
  }

  Membership? get _activeMembership {
    for (final m in memberships) {
      if (m.workspaceId == activeWorkspaceId) return m;
    }
    return null;
  }

  bool can(String permission) {
    final m = _activeMembership;
    if (m == null) return false;
    final role = rolesById[m.roleId];
    return role?.permissions[permission] == true;
  }

  Future<void> setUid(String? uid) async {
    if (uid == _uid) return;
    _uid = uid;
    _prefs ??= await SharedPreferences.getInstance();
    _memSub?.cancel();
    _wsSub?.cancel();
    _rolesSub?.cancel();
    if (uid == null) {
      memberships = [];
      workspaces = [];
      rolesById = {};
      activeWorkspaceId = null;
      loading = false;
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    _memSub = _db.collection('memberships').where('uid', isEqualTo: uid).snapshots().listen(
      (snap) {
        memberships = snap.docs.map(Membership.fromDoc).toList();
        _resolveActive();
        _subscribeWorkspaces();
        _subscribeRoles();
        loading = false;
        notifyListeners();
      },
      onError: (Object e) {
        error = e.toString();
        loading = false;
        notifyListeners();
      },
    );
  }

  void _resolveActive() {
    final ids = memberships.map((m) => m.workspaceId).toSet();
    if (activeWorkspaceId != null && ids.contains(activeWorkspaceId)) return;
    final saved = _prefs?.getString(_prefKey);
    if (saved != null && ids.contains(saved)) {
      activeWorkspaceId = saved;
    } else {
      activeWorkspaceId = memberships.isNotEmpty ? memberships.first.workspaceId : null;
    }
  }

  void _subscribeWorkspaces() {
    final ids = memberships.map((m) => m.workspaceId).toList();
    _wsSub?.cancel();
    if (ids.isEmpty) {
      workspaces = [];
      return;
    }
    // Firestore whereIn caps at 30 ids; workspaces per user stay small.
    _wsSub = _db
        .collection('workspaces')
        .where(FieldPath.documentId, whereIn: ids.take(30).toList())
        .snapshots()
        .listen((snap) {
      workspaces = snap.docs.map(Workspace.fromDoc).toList();
      notifyListeners();
    });
  }

  void _subscribeRoles() {
    if (activeWorkspaceId == null) return;
    _rolesSub?.cancel();
    _rolesSub = _db
        .collection('roles')
        .where('workspaceId', isEqualTo: activeWorkspaceId)
        .snapshots()
        .listen((snap) {
      rolesById = {for (final d in snap.docs) d.id: Role.fromDoc(d)};
      notifyListeners();
    });
  }

  Future<void> switchWorkspace(String id) async {
    activeWorkspaceId = id;
    await _prefs?.setString(_prefKey, id);
    _subscribeRoles();
    notifyListeners();
  }

  @override
  void dispose() {
    _memSub?.cancel();
    _wsSub?.cancel();
    _rolesSub?.cancel();
    super.dispose();
  }
}
