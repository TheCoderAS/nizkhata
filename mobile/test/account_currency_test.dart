// The account form and detail sheet in a workspace that is not Indian: the
// amount field carries the workspace's own symbol, and the India-only bank
// fields (IFSC, CIF) give way to a plain routing code. An INR workspace must
// read exactly as it always has.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nizkhata/core/theme.dart';
import 'package:nizkhata/data/models.dart';
import 'package:nizkhata/screens/account_form.dart';
import 'package:nizkhata/screens/accounts_screen.dart';
import 'package:nizkhata/state/workspace_controller.dart';

/// Stands in for the real controller, which reaches for Firebase as soon as it
/// is built. The form only ever asks it for the currency.
class _FakeWorkspace extends ChangeNotifier implements WorkspaceController {
  _FakeWorkspace(this.currency);

  @override
  final String currency;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Account _account({
  String type = 'bank',
  String? ifsc,
  String? cif,
  double? creditLimit,
}) =>
    Account(
      id: 'a1',
      workspaceId: 'ws',
      name: 'Main',
      type: type,
      openingBalance: 0,
      accountNumber: '001234567890',
      ifsc: ifsc,
      cif: cif,
      branchName: 'High Street',
      creditLimit: creditLimit,
    );

Future<void> _openForm(WidgetTester tester, String currency, {Account? existing}) async {
  // 360dp: the narrowest phone the app is laid out for.
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ChangeNotifierProvider<WorkspaceController>.value(
      value: _FakeWorkspace(currency),
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAccountForm(context, existing: existing),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The text field whose label is [label], found by its decoration so the
/// assertion is about the field itself, whether or not the prefix is painted.
TextField _field(WidgetTester tester, String label) => tester.widget<TextField>(
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label),
    );

void main() {
  group('bank details on the account form', () {
    testWidgets('an INR workspace asks for CIF and IFSC', (tester) async {
      await _openForm(tester, 'INR');
      expect(find.text('CIF'), findsOneWidget);
      expect(find.text('IFSC'), findsOneWidget);
      expect(find.text('Routing code (optional)'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a USD workspace asks for a routing code instead', (tester) async {
      await _openForm(tester, 'USD');
      expect(find.text('CIF'), findsNothing);
      expect(find.text('IFSC'), findsNothing);
      expect(find.text('Routing code (optional)'), findsOneWidget);
      expect(find.text('Sort code, BSB or SWIFT, whichever your bank uses'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a routing code already stored opens for editing', (tester) async {
      await _openForm(tester, 'GBP', existing: _account(ifsc: '12-34-56'));
      expect(find.text('12-34-56'), findsOneWidget);
    });
  });

  group('the credit limit field', () {
    for (final (currency, prefix) in [('INR', '₹ '), ('USD', '\$ '), ('AED', 'AED '), ('JPY', '¥ ')]) {
      testWidgets('carries the $currency symbol', (tester) async {
        await _openForm(tester, currency, existing: _account(type: 'credit_card'));
        expect(_field(tester, 'Credit limit (optional)').decoration!.prefixText, prefix);
      });
    }

    testWidgets('shows the symbol once there is a figure in it', (tester) async {
      await _openForm(tester, 'USD', existing: _account(type: 'credit_card', creditLimit: 5000));
      expect(find.text('\$ '), findsOneWidget);
      expect(find.text('₹ '), findsNothing);
    });
  });

  group('what the form saves for a bank account', () {
    test('an INR workspace keeps CIF and IFSC, as it always has', () {
      expect(
        bankDetailsData(indian: true, accountNumber: '1', cif: '99', ifsc: 'SBIN0000001', branchName: 'B'),
        {'accountNumber': '1', 'cif': '99', 'ifsc': 'SBIN0000001', 'branchName': 'B'},
      );
      // A cleared field is written as null, which clears it on an update.
      expect(bankDetailsData(indian: true).containsKey('cif'), isTrue);
    });

    test('elsewhere CIF is never written, so nothing stored is cleared', () {
      final data = bankDetailsData(indian: false, accountNumber: '1', ifsc: '021000021');
      expect(data.containsKey('cif'), isFalse);
      expect(data['ifsc'], '021000021');
    });
  });

  group('the account detail sheet', () {
    test('an INR workspace shows IFSC and CIF under their own names', () {
      final rows = accountDetailRows(_account(ifsc: 'SBIN0000001', cif: '99'), 'INR');
      expect(rows.map((e) => '${e.key}: ${e.value}'), [
        'Account number: 001234567890',
        'IFSC code: SBIN0000001',
        'CIF number: 99',
        'Branch name: High Street',
      ]);
    });

    test('a USD workspace shows the routing code and no CIF', () {
      final rows = accountDetailRows(_account(ifsc: '021000021', cif: '99'), 'USD');
      expect(rows.map((e) => '${e.key}: ${e.value}'), [
        'Account number: 001234567890',
        'Routing code: 021000021',
        'Branch name: High Street',
      ]);
    });

    test('a credit limit is written in the workspace currency', () {
      final rows = accountDetailRows(_account(type: 'credit_card', creditLimit: 1500000), 'USD');
      expect(rows.single.key, 'Credit limit');
      expect(rows.single.value, '\$1,500,000.00');
    });
  });
}
