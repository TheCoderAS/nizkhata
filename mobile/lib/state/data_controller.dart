// Workspace data — ports src/data/WorkspaceDataProvider.tsx. Streams every
// workspace-scoped collection for the active workspace and exposes the derived
// lookups (balanceOf / outstandingOf / settledOf / positionOf).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/derive.dart';
import '../data/models.dart';

class DataController extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _workspaceId;
  bool loading = true;
  String? error;

  List<Account> accounts = [];
  List<AppCategory> categories = [];
  List<Contact> contacts = [];
  List<Debt> debts = [];
  List<Due> dues = [];
  List<Budget> budgets = [];
  List<Txn> transactions = [];

  final List<StreamSubscription> _subs = [];

  Map<String, Debt> get debtsById => {for (final d in debts) d.id: d};
  Map<String, Account> get accountsById => {for (final a in accounts) a.id: a};
  Map<String, AppCategory> get categoriesById => {for (final c in categories) c.id: c};
  Map<String, Contact> get contactsById => {for (final c in contacts) c.id: c};

  double balanceOf(String accountId) {
    final byId = debtsById;
    var bal = accountsById[accountId]?.openingBalance ?? 0;
    for (final t in transactions) {
      bal += accountDeltas(t, byId)[accountId] ?? 0;
    }
    return roundMoney(bal);
  }

  double outstandingOf(String debtId) {
    final d = debtsById[debtId];
    if (d == null) return 0;
    return debtOutstanding(d, transactions);
  }

  double settledOf(String dueId) {
    for (final due in dues) {
      if (due.id == dueId) return dueSettledAmount(due, transactions);
    }
    return 0;
  }

  ContactPosition positionOf(String contactId) => contactPosition(contactId, debts, transactions);

  void setWorkspace(String? workspaceId) {
    if (workspaceId == _workspaceId) return;
    _workspaceId = workspaceId;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    if (workspaceId == null) {
      accounts = [];
      categories = [];
      contacts = [];
      debts = [];
      dues = [];
      budgets = [];
      transactions = [];
      loading = false;
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();

    Query q(String col) => _db.collection(col).where('workspaceId', isEqualTo: workspaceId);

    _subs.add(q('accounts').snapshots().listen((s) {
      accounts = s.docs.map(Account.fromDoc).toList();
      notifyListeners();
    }, onError: _onErr));
    _subs.add(q('categories').snapshots().listen((s) {
      categories = s.docs.map(AppCategory.fromDoc).toList();
      notifyListeners();
    }, onError: _onErr));
    _subs.add(q('contacts').snapshots().listen((s) {
      contacts = s.docs.map(Contact.fromDoc).toList();
      notifyListeners();
    }, onError: _onErr));
    _subs.add(q('debts').snapshots().listen((s) {
      debts = s.docs.map(Debt.fromDoc).toList();
      notifyListeners();
    }, onError: _onErr));
    _subs.add(q('dues').snapshots().listen((s) {
      dues = s.docs.map(Due.fromDoc).toList();
      notifyListeners();
    }, onError: _onErr));
    _subs.add(q('budgets').snapshots().listen((s) {
      budgets = s.docs.map(Budget.fromDoc).toList();
      notifyListeners();
    }, onError: _onErr));
    // Transactions drive the loading flag (largest / most important stream).
    _subs.add(q('transactions').snapshots().listen((s) {
      transactions = s.docs.map(Txn.fromDoc).toList();
      loading = false;
      notifyListeners();
    }, onError: _onErr));
  }

  void _onErr(Object e) {
    error = e.toString();
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
