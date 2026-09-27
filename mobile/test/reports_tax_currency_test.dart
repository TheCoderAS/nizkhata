// The Tax tab's India-only parts, TDS and the tax pack PDF, belong to INR
// workspaces. Everyone gets taxable totals by head and a CSV of them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nizkhata/data/derive.dart';
import 'package:nizkhata/data/models.dart';
import 'package:nizkhata/screens/reports_screen.dart';

import 'support/fake_controllers.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN', null);
  });

  Future<void> openTaxTab(WidgetTester tester, String currency, {int fyStartMonth = 4}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final today = DateTime.now();
    await tester.pumpWidget(providedApp(
      ws: FakeWorkspaceController(currency, fyStartMonth: fyStartMonth),
      data: FakeDataController(transactions: [
        Txn(
          id: 't1',
          workspaceId: 'ws',
          date: today,
          accountId: 'a1',
          totalAmount: 50000,
          hasSplit: false,
          financialYear: financialYearOf(today, fyStartMonth),
          lines: [
            TxnLine(
              lineId: 'l1',
              type: 'income',
              amount: 50000,
              tax: {'taxable': true, 'head': 'salary', 'tdsAmount': 5000, 'taxInclusive': false},
            ),
          ],
        ),
      ]),
      child: const ReportsScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tax'));
    await tester.pumpAndSettle();
  }

  testWidgets('an INR workspace sees TDS and the tax pack, exactly as before', (tester) async {
    await openTaxTab(tester, 'INR');
    expect(find.text('Total taxable'), findsOneWidget);
    expect(find.text('Total TDS'), findsOneWidget);
    expect(find.text('Tax pack PDF'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.text('TDS ₹5,000.00 · 1 line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a USD workspace sees taxable totals and a CSV, no TDS and no pack', (tester) async {
    await openTaxTab(tester, 'USD', fyStartMonth: 1);
    expect(find.text('Total taxable'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('\$50,000.00'), findsOneWidget);
    expect(find.text('1 line'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);

    expect(find.text('Total TDS'), findsNothing);
    expect(find.text('Tax pack PDF'), findsNothing);
    expect(find.textContaining('TDS'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
