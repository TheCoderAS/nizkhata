// Workspace data — ports src/data/WorkspaceDataProvider.tsx. Streams every
// workspace-scoped collection for the active workspace and exposes the derived
// lookups (balanceOf / outstandingOf / settledOf / positionOf).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/derive.dart';
import '../data/models.dart';

/// What the signed-in member may load: which modules their role can view, and
/// — for "own records only" roles — the contact their reads are limited to.
class DataScope {
  final bool restricted;
  final String? contactId;
  final Set<String> views;
  const DataScope({required this.restricted, this.contactId, required this.views});
  static const full = DataScope(restricted: false, views: {
    'transactions.view', 'dues.view', 'debts.view',
    'contacts.view', 'accounts.view', 'categories.view',
  });
  String get key => '$restricted|$contactId|${(views.toList()..sort()).join(',')}';
}

class DataController extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _workspaceId;
  String? _scopeKey;
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

  void setWorkspace(String? workspaceId, {DataScope scope = DataScope.full}) {
    if (workspaceId == _workspaceId && scope.key == _scopeKey) return;
    _workspaceId = workspaceId;
    _scopeKey = scope.key;
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
    // Reset so a role/scope change never leaves stale data from a wider scope.
    accounts = [];
    categories = [];
    contacts = [];
    debts = [];
    dues = [];
    budgets = [];
    transactions = [];
    notifyListeners();

    Query q(String col) => _db.collection(col).where('workspaceId', isEqualTo: workspaceId);

    // Restricted scope with no linked contact = nothing to show (and the
    // security rules deny broader reads anyway).
    final blockedRestricted = scope.restricted && scope.contactId == null;

    // Records tied to a contact get the own-contact filter when restricted —
    // this is what makes the query pass the record-level security rules.
    Query scoped(String col) {
      final base = q(col);
      return scope.restricted ? base.where('contactId', isEqualTo: scope.contactId) : base;
    }

    if (scope.views.contains('accounts.view') && !scope.restricted) {
      _subs.add(q('accounts').snapshots().listen((s) {
        accounts = s.docs.map(Account.fromDoc).toList();
        notifyListeners();
      }, onError: _onErr));
    }
    if (scope.views.contains('categories.view')) {
      _subs.add(q('categories').snapshots().listen((s) {
        categories = s.docs.map(AppCategory.fromDoc).toList();
        notifyListeners();
      }, onError: _onErr));
      if (!scope.restricted) {
        _subs.add(q('budgets').snapshots().listen((s) {
          budgets = s.docs.map(Budget.fromDoc).toList();
          notifyListeners();
        }, onError: _onErr));
      }
    }
    if (scope.views.contains('contacts.view') && !blockedRestricted) {
      final cq = scope.restricted ? q('contacts').where('id', isEqualTo: scope.contactId) : q('contacts');
      _subs.add(cq.snapshots().listen((s) {
        contacts = s.docs.map(Contact.fromDoc).toList();
        notifyListeners();
      }, onError: _onErr));
    }
    if (scope.views.contains('debts.view') && !blockedRestricted) {
      _subs.add(scoped('debts').snapshots().listen((s) {
        debts = s.docs.map(Debt.fromDoc).toList();
        notifyListeners();
      }, onError: _onErr));
    }
    if (scope.views.contains('dues.view') && !blockedRestricted) {
      _subs.add(scoped('dues').snapshots().listen((s) {
        dues = s.docs.map(Due.fromDoc).toList();
        notifyListeners();
      }, onError: _onErr));
    }
    if (scope.views.contains('transactions.view') && !blockedRestricted) {
      // Transactions drive the loading flag (largest / most important stream).
      _subs.add(scoped('transactions').snapshots().listen((s) {
        transactions = s.docs.map(Txn.fromDoc).toList();
        loading = false;
        notifyListeners();
      }, onError: _onErr));
    } else {
      loading = false;
      notifyListeners();
    }
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
