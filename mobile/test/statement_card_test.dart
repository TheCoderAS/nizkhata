// The statement summary that sits on top of a credit card's ledger. Pumped
// through the ledger screen's own widget so what is asserted is what ships.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nizkhata/core/theme.dart';
import 'package:nizkhata/data/models.dart';
import 'package:nizkhata/screens/account_ledger_screen.dart';

Account _card({int? statementDay = 5, int? paymentDueDay = 25, double? limit}) => Account(
      id: 'cc1',
      workspaceId: 'ws',
      name: 'HDFC Regalia',
      type: 'credit_card',
      openingBalance: 0,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      creditLimit: limit,
    );

Txn _spend(String id, DateTime date, double amount) => Txn(
      id: id,
      workspaceId: 'ws',
      date: date,
      accountId: 'cc1',
      totalAmount: -amount,
      hasSplit: false,
      financialYear: '2026-27',
      lines: [TxnLine(lineId: '${id}l', type: 'expense', amount: amount)],
    );

Txn _payment(String id, DateTime date, double amount) => Txn(
      id: id,
      workspaceId: 'ws',
      date: date,
      accountId: 'bank',
      totalAmount: -amount,
      hasSplit: false,
      financialYear: '2026-27',
      lines: [
        TxnLine(lineId: '${id}a', type: 'transfer_out', amount: amount, toAccountId: 'cc1'),
        TxnLine(lineId: '${id}b', type: 'transfer_in', amount: amount, toAccountId: 'cc1'),
      ],
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN', null);
  });

  Future<void> pump(WidgetTester tester, Account card, List<Txn> txns) async {
    // 360dp: the row of figures has to survive a real phone.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: StatementSummary(
          card: card,
          txns: txns,
          debtsById: const {},
          currency: 'INR',
          // Pinned rather than DateTime.now(), so the assertions below mean the
          // same thing in every month this suite is ever run.
          now: DateTime(2026, 9, 20),
        ),
      ),
    ));
  }

  testWidgets('names the statement it is showing', (tester) async {
    await pump(tester, _card(), [_spend('t1', DateTime(2026, 8, 20), 3000)]);
    expect(find.text('Statement of 5 Sept 2026'), findsOneWidget);
  });

  testWidgets('shows what was owed on the statement day, not what is owed now', (tester) async {
    await pump(tester, _card(), [
      _spend('t1', DateTime(2026, 8, 20), 3000),
      // After the statement: next month's bill, so not in the headline figure.
      _spend('t2', DateTime(2026, 9, 10), 1200),
    ]);
    expect(find.text('₹3,000.00'), findsOneWidget);
    expect(find.text('₹1,200.00 spent since, on the next bill'), findsOneWidget);
  });

  testWidgets('says nothing about later spending when there is none', (tester) async {
    await pump(tester, _card(), [_spend('t1', DateTime(2026, 8, 20), 3000)]);
    expect(find.textContaining('spent since'), findsNothing);
  });

  testWidgets('counts down to the payment date', (tester) async {
    await pump(tester, _card(), [_spend('t1', DateTime(2026, 8, 20), 3000)]);
    // 20 Sept to 25 Sept.
    expect(find.text('Due in 5 days · by 25 Sept 2026'), findsOneWidget);
  });

  testWidgets('calls an overdue bill overdue', (tester) async {
    // Billed on the 25th, due on the 12th — September's bill was due 12 Oct,
    // so on 20 Sept the live bill is August's, due 12 September.
    await pump(
      tester,
      _card(statementDay: 25, paymentDueDay: 12),
      [_spend('t1', DateTime(2026, 8, 20), 3000)],
    );
    expect(find.textContaining('Overdue by 8 days'), findsOneWidget);
  });

  testWidgets('a paid off card is not asking for anything', (tester) async {
    await pump(tester, _card(), [
      _spend('t1', DateTime(2026, 8, 20), 3000),
      _payment('p1', DateTime(2026, 8, 28), 3000),
    ]);
    expect(find.text('Nothing to pay'), findsOneWidget);
    // No date nagging on a bill with nothing to pay.
    expect(find.textContaining('Due in'), findsNothing);
  });

  group('the credit limit', () {
    testWidgets('is left out entirely when the card has none', (tester) async {
      await pump(tester, _card(), [_spend('t1', DateTime(2026, 8, 20), 3000)]);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('used'), findsNothing);
    });

    testWidgets('shows utilisation against the current balance', (tester) async {
      await pump(tester, _card(limit: 100000), [
        _spend('t1', DateTime(2026, 8, 20), 3000),
        _spend('t2', DateTime(2026, 9, 10), 22000),
      ]);
      // Utilisation is what the bank sees today: 25,000 of 1,00,000.
      expect(find.text('25% of ₹1,00,000.00 used'), findsOneWidget);
      expect(find.text('₹75,000.00 left'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  testWidgets('a card with no cycle set up renders nothing at all', (tester) async {
    await pump(tester, _card(statementDay: null), [_spend('t1', DateTime(2026, 8, 20), 3000)]);
    expect(find.textContaining('Statement'), findsNothing);
  });
}
