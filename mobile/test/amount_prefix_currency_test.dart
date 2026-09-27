// Every amount field names the workspace's currency, not India's. These are
// the sheets outside the line editor that take an amount: recording a debt
// repayment, recording a due payment, and a new debt's opening amount.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nizkhata/data/models.dart';
import 'package:nizkhata/screens/debt_form.dart';
import 'package:nizkhata/screens/debts_screen.dart';
import 'package:nizkhata/screens/dues_screen.dart';

import 'support/fake_controllers.dart';

final _debt = Debt(
  id: 'd1',
  workspaceId: 'ws',
  contactId: 'c1',
  direction: 'owe',
  purpose: 'loan',
  principal: 1000,
  status: 'open',
  label: 'Car loan',
);

final _due = Due(
  id: 'u1',
  workspaceId: 'ws',
  direction: 'payable',
  title: 'Rent',
  amount: 1200,
  dueDate: DateTime(2026, 9, 1),
  status: 'open',
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN', null);
  });

  /// Opens [open] from a button on a 360dp phone, in a workspace keeping
  /// books in [currency].
  Future<void> openSheet(
    WidgetTester tester,
    String currency,
    void Function(BuildContext) open,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(providedApp(
      ws: FakeWorkspaceController(currency),
      data: FakeDataController(
        debts: [_debt],
        dues: [_due],
        contacts: [Contact(id: 'c1', workspaceId: 'ws', name: 'Asha', type: 'person')],
        accounts: [Account(id: 'a1', workspaceId: 'ws', name: 'Bank', type: 'bank', openingBalance: 0)],
        outstanding: {'d1': 1000},
      ),
      child: Scaffold(
        body: Builder(
          builder: (context) => TextButton(onPressed: () => open(context), child: const Text('Open')),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  final sheets = <String, void Function(BuildContext)>{
    'debt repayment': (c) => showDebtPayment(c, _debt),
    'due payment': (c) => showDuePayment(c, _due),
    'new debt': (c) => showDebtForm(c),
  };

  for (final e in sheets.entries) {
    group(e.key, () {
      testWidgets('is in rupees in an INR workspace, exactly as before', (tester) async {
        await openSheet(tester, 'INR', e.value);
        expect(find.text('₹ '), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('is in dollars in a USD workspace', (tester) async {
        await openSheet(tester, 'USD', e.value);
        expect(find.text('\$ '), findsOneWidget);
        expect(find.text('₹ '), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('is in euros in a EUR workspace', (tester) async {
        await openSheet(tester, 'EUR', e.value);
        expect(find.text('€ '), findsOneWidget);
        expect(find.text('₹ '), findsNothing);
      });
    });
  }
}
