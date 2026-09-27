// Stand-ins for the two Firestore-backed controllers, so a screen can be
// pumped in a widget test without Firebase. The real ones open a Firestore
// connection as soon as they are constructed; these hold plain lists and
// answer only what the screens under test ask. Anything else throws, which
// is the point: a test that reaches further than it meant to fails loudly.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nizkhata/core/theme.dart';
import 'package:nizkhata/data/models.dart';
import 'package:nizkhata/state/data_controller.dart';
import 'package:nizkhata/state/workspace_controller.dart';

class FakeWorkspaceController extends ChangeNotifier implements WorkspaceController {
  FakeWorkspaceController(this.currency, {this.fyStartMonth = 4});

  @override
  final String currency;
  @override
  final int fyStartMonth;

  @override
  Workspace? get activeWorkspace => Workspace(
        id: 'ws',
        name: 'Test books',
        ownerId: 'u1',
        baseCurrency: currency,
        fyStartMonth: fyStartMonth,
      );

  @override
  String? get activeWorkspaceId => 'ws';

  /// Every permission, so nothing on screen is hidden for a reason the test
  /// is not about.
  @override
  bool can(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDataController extends ChangeNotifier implements DataController {
  FakeDataController({
    List<Account>? accounts,
    List<AppCategory>? categories,
    List<Contact>? contacts,
    List<Debt>? debts,
    List<Due>? dues,
    List<Txn>? transactions,
    this.outstanding = const {},
    this.settled = const {},
  })  : accounts = accounts ?? [],
        categories = categories ?? [],
        contacts = contacts ?? [],
        debts = debts ?? [],
        dues = dues ?? [],
        transactions = transactions ?? [];

  @override
  List<Account> accounts;
  @override
  List<AppCategory> categories;
  @override
  List<Contact> contacts;
  @override
  List<Debt> debts;
  @override
  List<Due> dues;
  @override
  List<Txn> transactions;

  final Map<String, double> outstanding;
  final Map<String, double> settled;

  @override
  Map<String, Debt> get debtsById => {for (final d in debts) d.id: d};
  @override
  Map<String, Account> get accountsById => {for (final a in accounts) a.id: a};
  @override
  Map<String, AppCategory> get categoriesById => {for (final c in categories) c.id: c};
  @override
  Map<String, Contact> get contactsById => {for (final c in contacts) c.id: c};

  @override
  double outstandingOf(String debtId) => outstanding[debtId] ?? 0;
  @override
  double settledOf(String dueId) => settled[dueId] ?? 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A phone-sized app around [child] with both controllers provided.
Widget providedApp({
  required WorkspaceController ws,
  required DataController data,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<WorkspaceController>.value(value: ws),
      ChangeNotifierProvider<DataController>.value(value: data),
    ],
    child: MaterialApp(theme: buildDarkTheme(), home: child),
  );
}
