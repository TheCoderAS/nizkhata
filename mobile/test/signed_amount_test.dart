// A receivable and a payable have to be told apart without reading a word.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nizkhata/core/theme.dart';
import 'package:nizkhata/widgets/common.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN', null);
  });

  Future<void> pump(WidgetTester tester, {required bool inbound, double amount = 1500}) =>
      tester.pumpWidget(MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: SignedAmount(amount: amount, inbound: inbound, currency: 'INR'),
        ),
      ));

  Text amountText(WidgetTester tester) => tester.widget<Text>(find.byType(Text));
  Icon arrow(WidgetTester tester) => tester.widget<Icon>(find.byType(Icon));

  group('money coming in', () {
    testWidgets('reads plainly, in the positive tone', (tester) async {
      await pump(tester, inbound: true);
      expect(find.text('₹1,500.00'), findsOneWidget);
      expect(amountText(tester).style?.color, AppColors.accent2);
    });

    testWidgets('points inward, so colour is not doing the work alone', (tester) async {
      await pump(tester, inbound: true);
      expect(arrow(tester).icon, Icons.south_west);
      expect(arrow(tester).color, AppColors.accent2);
    });
  });

  group('money going out', () {
    testWidgets('is parenthesised, the way a ledger writes a negative', (tester) async {
      await pump(tester, inbound: false);
      expect(find.text('(₹1,500.00)'), findsOneWidget);
      expect(amountText(tester).style?.color, AppColors.danger);
    });

    testWidgets('points outward', (tester) async {
      await pump(tester, inbound: false);
      expect(arrow(tester).icon, Icons.north_east);
      expect(arrow(tester).color, AppColors.danger);
    });
  });

  testWidgets('takes a magnitude, whatever sign it is handed', (tester) async {
    // Callers pass an outstanding figure, which is always positive; a stray
    // negative must not flip the direction the caller asked for.
    await pump(tester, inbound: false, amount: -1500);
    expect(find.text('(₹1,500.00)'), findsOneWidget);
    await pump(tester, inbound: true, amount: -1500);
    expect(find.text('₹1,500.00'), findsOneWidget);
  });

  group('a debt that has been paid off', () {
    testWidgets('is neither, so it points nowhere and takes no tone', (tester) async {
      await pump(tester, inbound: false, amount: 0);
      // The bug this replaced: an outbound arrow in the colour of money owed,
      // next to a dash, on a debt that had been cleared.
      expect(find.byType(Icon), findsNothing);
      expect(amountText(tester).style?.color, isNot(AppColors.danger));
      expect(amountText(tester).style?.color, isNot(AppColors.accent2));
    });

    testWidgets('reads as a dash, the way a ledger writes nil', (tester) async {
      await pump(tester, inbound: true, amount: 0);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('tells a screen reader it is settled', (tester) async {
      await pump(tester, inbound: false, amount: 0);
      expect(find.bySemanticsLabel('Settled'), findsOneWidget);
    });

    testWidgets('treats a rounding crumb as nil', (tester) async {
      await pump(tester, inbound: false, amount: 0.004);
      expect(find.byType(Icon), findsNothing);
    });
  });

  testWidgets('says the word for a reader who cannot see the colour', (tester) async {
    // Colour and an arrow are no use to a screen reader; the semantics label
    // is where the text still belongs.
    await pump(tester, inbound: true);
    expect(find.bySemanticsLabel('Receivable ₹1,500.00'), findsOneWidget);
    await pump(tester, inbound: false);
    expect(find.bySemanticsLabel('Payable ₹1,500.00'), findsOneWidget);
  });

  testWidgets('does not leak the raw figure past the label', (tester) async {
    // Without ExcludeSemantics the reader would announce the amount twice.
    await pump(tester, inbound: false);
    expect(find.bySemanticsLabel('(₹1,500.00)'), findsNothing);
  });
}
