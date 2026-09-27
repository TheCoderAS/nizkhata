// The line editor writes amounts in the workspace's own currency, and asks
// for India's tax details (TDS, the perquisite head) only in an INR workspace.
// Whatever it stops asking for, it must never throw away: a line that already
// carries TDS keeps it through any edit.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nizkhata/data/models.dart';
import 'package:nizkhata/widgets/txn_lines_editor.dart';

import 'support/fake_controllers.dart';

TxnLine _taxedIncome({String id = 'l1', double amount = 50000, String head = 'salary', double tds = 5000}) =>
    TxnLine(
      lineId: id,
      type: 'income',
      amount: amount,
      tax: {'taxable': true, 'head': head, 'tdsAmount': tds, 'taxInclusive': true},
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN', null);
  });

  // A 360dp phone, the narrowest the app is laid out for.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpEditor(WidgetTester tester, String currency, List<LineDraft> lines) async {
    phone(tester);
    await tester.pumpWidget(providedApp(
      ws: FakeWorkspaceController(currency),
      data: FakeDataController(),
      child: Scaffold(
        body: SingleChildScrollView(
          // No side padding: the test font draws every glyph a full em wide,
          // which is wider than any real font, and the Type picker's longest
          // label would overflow for that reason alone.
          child: StatefulBuilder(
            builder: (context, setState) => TxnLinesEditor(
              lines: lines,
              accountId: 'acc1',
              contactId: null,
              onChanged: () => setState(() {}),
            ),
          ),
        ),
      ),
    ));
  }

  group('the amount prefix follows the workspace currency', () {
    testWidgets('rupees in an INR workspace, exactly as before', (tester) async {
      await pumpEditor(tester, 'INR', [LineDraft(type: 'expense')]);
      expect(find.text('₹ '), findsOneWidget);
      expect(find.text('\$ '), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dollars in a USD workspace', (tester) async {
      await pumpEditor(tester, 'USD', [LineDraft(type: 'expense')]);
      expect(find.text('\$ '), findsOneWidget);
      expect(find.text('₹ '), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a code-symbol currency keeps its gap', (tester) async {
      await pumpEditor(tester, 'AED', [LineDraft(type: 'expense')]);
      expect(find.text('AED '), findsOneWidget);
    });

    testWidgets('split lines total in the workspace currency', (tester) async {
      final a = LineDraft(type: 'expense')..amount.text = '12';
      final b = LineDraft(type: 'expense')..amount.text = '30';
      await pumpEditor(tester, 'USD', [a, b]);
      expect(find.text('(\$12.00)'), findsOneWidget);
      expect(find.text('(\$30.00)'), findsOneWidget);
    });
  });

  group('TDS', () {
    testWidgets('is asked for in an INR workspace', (tester) async {
      await pumpEditor(tester, 'INR', draftsFromLines([_taxedIncome()]));
      expect(find.widgetWithText(TextFormField, 'TDS'), findsOneWidget);
      // Amount and TDS both in rupees.
      expect(find.text('₹ '), findsNWidgets(2));
      expect(find.text('5000'), findsOneWidget);
    });

    testWidgets('is not asked for in a USD workspace', (tester) async {
      await pumpEditor(tester, 'USD', draftsFromLines([_taxedIncome()]));
      expect(find.text('Tax info'), findsOneWidget);
      expect(find.text('Head'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'TDS'), findsNothing);
      expect(find.text('\$ '), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stored TDS survives an inline edit where it is hidden', (tester) async {
      final lines = draftsFromLines([_taxedIncome()]);
      await pumpEditor(tester, 'USD', lines);

      await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '52000');
      await tester.pump();

      final tax = lineMapsFromDrafts(lines, 1).single['tax'] as Map<String, dynamic>;
      expect(tax, {'taxable': true, 'head': 'salary', 'tdsAmount': 5000.0, 'taxInclusive': true});
      expect(lines.single.amountValue, 52000);
    });

    testWidgets('stored TDS survives the line sheet, which edits a copy', (tester) async {
      final lines = draftsFromLines([
        _taxedIncome(id: 'l1', head: 'perquisite', tds: 750),
        TxnLine(lineId: 'l2', type: 'expense', amount: 100),
      ]);
      await pumpEditor(tester, 'USD', lines);

      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      expect(find.text('Edit line'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'TDS'), findsNothing);

      await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '9000');
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final map = lineMapsFromDrafts(lines, 1).first;
      expect(map['amount'], 9000);
      expect(map['tax'], {'taxable': true, 'head': 'perquisite', 'tdsAmount': 750.0, 'taxInclusive': true});
    });
  });

  group('tax heads', () {
    test('an INR workspace is offered every head, perquisite included', () {
      expect(taxHeadsFor('INR'), same(kTaxHeads));
      expect(taxHeadsFor('INR').containsKey('perquisite'), true);
    });

    test('elsewhere the India-only heads are left out and the universal ones kept', () {
      final heads = taxHeadsFor('USD');
      expect(heads.containsKey('perquisite'), false);
      for (final h in ['salary', 'bonus', 'dividend', 'capital_gains', 'interest', 'rent', 'other']) {
        expect(heads.containsKey(h), true, reason: h);
      }
      // Order is kept, so the list reads the same minus one entry.
      expect(heads.keys.toList(), kTaxHeads.keys.where((k) => k != 'perquisite').toList());
    });

    test('a head a line already carries is still offered, so it is never blanked', () {
      expect(taxHeadsFor('USD', current: 'perquisite').containsKey('perquisite'), true);
    });

    testWidgets('a stored India-only head still shows as chosen', (tester) async {
      await pumpEditor(tester, 'GBP', draftsFromLines([_taxedIncome(head: 'perquisite')]));
      final field = tester.widget<DropdownButton<String>>(find.descendant(
          of: find.byType(DropdownButtonFormField<String>).last,
          matching: find.byType(DropdownButton<String>)));
      expect(field.value, 'perquisite');
    });
  });
}
