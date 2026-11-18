// Store screenshots, rendered from the app's real screens.
//
// Pumps the actual router shell and screens with a believable sample
// workspace, using in-memory stand-ins for the two Firestore controllers
// (balances, outstanding debts and settled dues are computed with the app's
// own derive functions), with the app's real fonts and icons loaded, and
// saves each screen as a phone-resolution PNG.
//
// Kept out of test/ so CI does not run it. Generate with:
//   flutter test test_store/store_screenshots_test.dart --dart-define=SHOTS_OUT=<dir> \
//     --dart-define=FONTS_DIR=<dir with Inter-400..800.ttf> \
//     --dart-define=ICONS_FONT=<path to MaterialIcons-Regular.otf>

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nizkhata/core/currency.dart' as cur;
import 'package:nizkhata/core/theme.dart';
import 'package:nizkhata/data/derive.dart';
import 'package:nizkhata/data/models.dart';
import 'package:nizkhata/screens/account_ledger_screen.dart';
import 'package:nizkhata/screens/budgets_screen.dart';
import 'package:nizkhata/screens/calendar_screen.dart';
import 'package:nizkhata/screens/contact_detail_screen.dart';
import 'package:nizkhata/screens/dashboard_screen.dart';
import 'package:nizkhata/screens/debts_screen.dart';
import 'package:nizkhata/screens/dues_screen.dart';
import 'package:nizkhata/screens/reports_screen.dart';
import 'package:nizkhata/screens/shell.dart';
import 'package:nizkhata/screens/transactions_screen.dart';
import 'package:nizkhata/state/data_controller.dart';
import 'package:nizkhata/state/workspace_controller.dart';

const _out = String.fromEnvironment('SHOTS_OUT');
const _fontsDir = String.fromEnvironment('FONTS_DIR');
const _iconsFont = String.fromEnvironment('ICONS_FONT');

// ---------------------------------------------------------------- sample data

const ws = 'home';
DateTime d(int m, int day) => DateTime(2026, m, day);

final accounts = [
  Account(id: 'hdfc', workspaceId: ws, name: 'HDFC Savings', type: 'bank', openingBalance: 182400, accountNumber: '50100234417'),
  Account(id: 'cash', workspaceId: ws, name: 'Cash', type: 'cash', openingBalance: 6200),
  Account(
    id: 'visa',
    workspaceId: ws,
    name: 'HDFC Regalia Visa',
    type: 'credit_card',
    openingBalance: 0,
    cardLast4: '4417',
    statementDay: 14,
    paymentDueDay: 30,
    creditLimit: 150000,
  ),
];

AppCategory cat(String id, String name, String kind) =>
    AppCategory(id: id, workspaceId: ws, name: name, kind: kind, isSystem: false);
final categories = [
  cat('salary', 'Salary', 'income'),
  cat('interest', 'Interest', 'income'),
  cat('freelance', 'Freelance', 'income'),
  cat('groceries', 'Groceries', 'expense'),
  cat('food', 'Eating out', 'expense'),
  cat('rent', 'Rent', 'expense'),
  cat('utilities', 'Utilities', 'expense'),
  cat('household', 'Household', 'expense'),
  cat('fuel', 'Fuel', 'expense'),
  cat('shopping', 'Shopping', 'expense'),
  cat('education', 'Education', 'expense'),
  cat('fees', 'Fees', 'expense'),
];

final contacts = [
  Contact(id: 'kabir', workspaceId: ws, name: 'Kabir Mehta', type: 'individual', relationship: 'Friend', phone: '+91 98200 41733'),
  Contact(id: 'meera', workspaceId: ws, name: 'Meera Sharma', type: 'individual', relationship: 'Sister', phone: '+91 99300 18264'),
  Contact(id: 'rao', workspaceId: ws, name: 'Mr. Rao', type: 'individual', relationship: 'Landlord'),
  Contact(id: 'school', workspaceId: ws, name: 'Greenfield School', type: 'business'),
];

final debts = [
  Debt(id: 'kabir-loan', workspaceId: ws, contactId: 'kabir', direction: 'owed', purpose: 'loan', principal: 16000, status: 'open', label: 'Loan for his bike'),
  Debt(id: 'meera-loan', workspaceId: ws, contactId: 'meera', direction: 'owe', purpose: 'loan', principal: 25000, status: 'open', label: 'For the deposit'),
];

int _n = 0;
TxnLine line(String type, double amount, {String? cat, String? debt, String? to, String? note}) =>
    TxnLine(lineId: 'l${_n++}', type: type, amount: amount, categoryId: cat, debtId: debt, toAccountId: to, note: note);

Txn txn(String id, DateTime date, String account, double total, List<TxnLine> lines, {String? note, String? contact}) => Txn(
      id: id,
      workspaceId: ws,
      date: date,
      accountId: account,
      totalAmount: total,
      hasSplit: lines.length > 1,
      financialYear: financialYearOf(date, 4),
      lines: lines,
      note: note,
      contactId: contact,
    );

List<Txn> buildTxns() {
  final t = <Txn>[];
  // Six months of the regulars, so reports have a shape.
  for (final m in [4, 5, 6, 7, 8, 9, 10, 11]) {
    t.add(txn('sal$m', d(m, 1), 'hdfc', 85000, [line('income', 85000, cat: 'salary')], note: 'Salary'));
    t.add(txn('rent$m', d(m, 5), 'hdfc', -22000, [line('expense', 22000, cat: 'rent')], note: 'Rent', contact: 'rao'));
    t.add(txn('elec$m', d(m, 10), 'hdfc', -(1900 + m * 80.0), [line('expense', 1900 + m * 80.0, cat: 'utilities')], note: 'Electricity'));
    t.add(txn('groc$m', d(m, 13), 'hdfc', -(6800 + (m % 3) * 900.0), [line('expense', 6800 + (m % 3) * 900.0, cat: 'groceries')], note: 'Monthly groceries'));
    t.add(txn('food$m', d(m, 15), 'cash', -(1200 + (m % 2) * 650.0), [line('expense', 1200 + (m % 2) * 650.0, cat: 'food')], note: 'Dinner out'));
  }
  t.add(txn('fuel11', d(11, 6), 'hdfc', -2800, [line('expense', 2800, cat: 'fuel')], note: 'Fuel'));
  t.add(txn('shop11', d(11, 7), 'hdfc', -3450, [line('expense', 3450, cat: 'shopping')], note: 'New shoes'));
  t.add(txn('fd', d(10, 31), 'hdfc', 3120, [line('income', 3120, cat: 'interest')], note: 'FD interest'));
  t.add(txn('freelance', d(11, 8), 'hdfc', 18000, [line('income', 18000, cat: 'freelance')], note: 'Logo design project'));
  // Debts.
  t.add(txn('meera-borrow', d(8, 3), 'hdfc', 25000, [line('borrow', 25000, debt: 'meera-loan')], note: 'Borrowed for the deposit', contact: 'meera'));
  t.add(txn('meera-repay', d(10, 3), 'hdfc', -10000, [line('repayment', 10000, debt: 'meera-loan')], note: 'Paid back part', contact: 'meera'));
  t.add(txn('kabir-lend', d(10, 2), 'hdfc', -16000, [line('lend', 16000, debt: 'kabir-loan')], note: 'Loan for his bike', contact: 'kabir'));
  t.add(txn('kabir-repay', d(11, 9), 'hdfc', 15000, [line('repayment', 15000, debt: 'kabir-loan')], note: 'Kabir repaid', contact: 'kabir'));
  // The card: October's bill paid, November's statement drawn on the 14th.
  t.add(txn('v1', d(10, 18), 'visa', -3400, [line('expense', 3400, cat: 'fuel')], note: 'Fuel'));
  t.add(txn('v2', d(10, 26), 'visa', -6290, [line('expense', 6290, cat: 'shopping')], note: 'Diwali shopping'));
  t.add(txn('v3', d(11, 2), 'visa', -3940, [line('expense', 3940, cat: 'food')], note: 'Dinner at Toit', contact: 'kabir'));
  t.add(txn('v4', d(11, 12), 'visa', -4820, [
    line('expense', 2796, cat: 'groceries', note: 'Groceries'),
    line('expense', 1446, cat: 'household', note: 'Household'),
    line('fee', 578, cat: 'fees', note: 'Delivery fee'),
  ], note: 'Fresh Mart'));
  t.add(txn('v5', d(11, 16), 'visa', -1260, [line('expense', 1260, cat: 'food')], note: 'Lunch'));
  // Paying a card bill is a transfer from the bank to the card.
  t.add(txn('vpay', d(10, 29), 'hdfc', -9750, [
    line('transfer_out', 9750, to: 'visa'),
    line('transfer_in', 9750, to: 'visa'),
  ], note: 'Card bill payment'));
  t.add(txn('vprev', d(10, 8), 'visa', -9750, [line('expense', 9750, cat: 'shopping')], note: 'Flight tickets'));
  return t;
}

final dues = [
  Due(id: 'school', workspaceId: ws, direction: 'payable', title: 'School fees · Term 2', amount: 18000, dueDate: d(11, 18), status: 'open', contactId: 'school'),
  Due(id: 'elec', workspaceId: ws, direction: 'payable', title: 'Electricity · Nov', amount: 2400, dueDate: d(11, 20), status: 'open', recurrence: 'monthly'),
  Due(id: 'kabir-share', workspaceId: ws, direction: 'receivable', title: "Kabir's share of dinner", amount: 1970, dueDate: d(11, 25), status: 'open', contactId: 'kabir'),
  Due(id: 'stmt_visa_20261114', workspaceId: ws, direction: 'payable', title: 'HDFC Regalia Visa bill', amount: 18450, dueDate: d(11, 30), status: 'open'),
  Due(id: 'rent-dec', workspaceId: ws, direction: 'payable', title: 'Rent · Dec', amount: 22000, dueDate: d(12, 5), status: 'open', contactId: 'rao', recurrence: 'monthly'),
  Due(id: 'meera-due', workspaceId: ws, direction: 'payable', title: 'Meera · next instalment', amount: 5000, dueDate: d(12, 3), status: 'open', contactId: 'meera'),
  Due(id: 'insurance', workspaceId: ws, direction: 'payable', title: 'Health insurance', amount: 14200, dueDate: d(12, 12), status: 'open', recurrence: 'yearly'),
];

final budgets = [
  Budget(id: 'b1', workspaceId: ws, categoryId: 'groceries', amount: 12000, period: 'monthly'),
  Budget(id: 'b2', workspaceId: ws, categoryId: 'food', amount: 6500, period: 'monthly'),
  Budget(id: 'b3', workspaceId: ws, categoryId: 'shopping', amount: 8000, period: 'monthly'),
  Budget(id: 'b4', workspaceId: ws, categoryId: 'fuel', amount: 5000, period: 'monthly'),
];

// ------------------------------------------------------- in-memory controllers

class ShotWorkspace extends ChangeNotifier implements WorkspaceController {
  @override
  String get currency => 'INR';
  @override
  int get fyStartMonth => 4;
  @override
  cur.CurrencySpec get currencySpec => cur.currencySpec('INR');
  @override
  Workspace? get activeWorkspace =>
      Workspace(id: ws, name: 'Sharma Household', ownerId: 'u1', baseCurrency: 'INR', fyStartMonth: 4);
  @override
  String? get activeWorkspaceId => ws;
  @override
  bool can(String permission) => true;
  @override
  bool loading = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ShotData extends ChangeNotifier implements DataController {
  @override
  List<Account> accounts = [...accounts_];
  @override
  List<AppCategory> categories = [...categories_];
  @override
  List<Contact> contacts = [...contacts_];
  @override
  List<Debt> debts = [...debts_];
  @override
  List<Due> dues = [...dues_];
  @override
  List<Budget> budgets = [...budgets_];
  @override
  List<Txn> transactions = buildTxns();
  @override
  bool loading = false;
  @override
  String? error;

  @override
  Map<String, Debt> get debtsById => {for (final x in debts) x.id: x};
  @override
  Map<String, Account> get accountsById => {for (final x in accounts) x.id: x};
  @override
  Map<String, AppCategory> get categoriesById => {for (final x in categories) x.id: x};
  @override
  Map<String, Contact> get contactsById => {for (final x in contacts) x.id: x};

  @override
  double balanceOf(String accountId) {
    final byId = debtsById;
    var bal = accountsById[accountId]?.openingBalance ?? 0;
    for (final t in transactions) {
      bal += accountDeltas(t, byId)[accountId] ?? 0;
    }
    return roundMoney(bal);
  }

  @override
  double outstandingOf(String debtId) {
    final x = debtsById[debtId];
    return x == null ? 0 : debtOutstanding(x, transactions);
  }

  @override
  double settledOf(String dueId) {
    for (final due in dues) {
      if (due.id == dueId) return dueSettledAmount(due, transactions);
    }
    return 0;
  }

  @override
  ContactPosition positionOf(String contactId) => contactPosition(contactId, debts, transactions);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final accounts_ = accounts, categories_ = categories, contacts_ = contacts, debts_ = debts, dues_ = dues, budgets_ = budgets;

// ------------------------------------------------------------------ rendering

GoRouter shotRouter(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/accounts/:id/ledger', builder: (_, s) => AccountLedgerScreen(accountId: s.pathParameters['id']!)),
        GoRoute(path: '/contacts/:id', builder: (_, s) => ContactDetailScreen(contactId: s.pathParameters['id']!)),
        GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
        GoRoute(path: '/budgets', builder: (_, __) => const BudgetsScreen()),
        GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
        ShellRoute(
          builder: (context, state, child) => AppShell(state: state, child: child),
          routes: [
            GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
            GoRoute(path: '/transactions', builder: (_, __) => const TransactionsScreen()),
            GoRoute(path: '/dues', builder: (_, __) => const DuesScreen()),
            GoRoute(path: '/debts', builder: (_, __) => const DebtsScreen()),
          ],
        ),
      ],
    );

ThemeData shotTheme() {
  final t = buildDarkTheme();
  return t.copyWith(
    textTheme: t.textTheme.apply(fontFamily: 'Inter'),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamily: 'Inter'),
  );
}

Future<void> loadFonts() async {
  ByteData bytes(String path) => ByteData.sublistView(File(path).readAsBytesSync());
  // One family with every weight, for the shot theme...
  final inter = FontLoader('Inter');
  for (final w in [400, 500, 600, 700, 800]) {
    inter.addFont(Future.value(bytes('$_fontsDir/Inter-$w.ttf')));
  }
  await inter.load();
  // ...and each weight under the family name google_fonts gives it, so
  // styles the app builds with GoogleFonts.inter(...) find it too.
  const variants = {400: 'regular', 500: '500', 600: '600', 700: '700', 800: '800'};
  for (final e in variants.entries) {
    await (FontLoader('Inter_${e.value}')..addFont(Future.value(bytes('$_fontsDir/Inter-${e.key}.ttf')))).load();
  }
  await (FontLoader('MaterialIcons')..addFont(Future.value(bytes(_iconsFont)))).load();
}

void main() {
  setUpAll(() async {
    // Inter is loaded from local files below; the theme's own Google Fonts
    // lookup must not try the network, which tests block.
    GoogleFonts.config.allowRuntimeFetching = false;
    // ...and its complaint that the asset is missing is expected: the theme
    // gets Inter from the FontLoader instead. Anything else still fails.
    final report = reportTestException;
    reportTestException = (details, description) {
      if ('${details.exception}'.contains('allowRuntimeFetching is false')) return;
      report(details, description);
    };
    // Screens remember view choices in shared preferences; start them empty.
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting();
    await loadFonts();
  });

  // 1080 x 2340: a common 19.5:9 phone.
  const size = Size(1080, 2340);
  const dpr = 2.75;

  final shots = {
    '1-dashboard': '/dashboard',
    '2-transactions': '/transactions',
    '3-dues': '/dues',
    '4-card-statement': '/accounts/visa/ledger',
    '5-person-ledger': '/contacts/kabir',
    '6-debts': '/debts',
    '7-reports': '/reports',
    '8-budgets': '/budgets',
  };

  for (final e in shots.entries) {
    testWidgets(e.key, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<WorkspaceController>.value(value: ShotWorkspace()),
            ChangeNotifierProvider<DataController>.value(value: ShotData()),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: shotTheme(),
            darkTheme: shotTheme(),
            themeMode: ThemeMode.dark,
            routerConfig: shotRouter(e.value),
          ),
        ),
      ));
      // Let entrance animations finish without waiting on repeating ones.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: dpr);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        return png!.buffer.asUint8List();
      });
      File('$_out/${e.key}.png').writeAsBytesSync(bytes!);
    });
  }
}
