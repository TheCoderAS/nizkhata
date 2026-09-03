import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nizkhata/core/theme.dart';
import 'package:nizkhata/widgets/token_assist.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN', null);
  });

  late TextEditingController controller;

  Future<void> pump(
    WidgetTester tester, {
    String text = '',
    bool repeats = true,
    DateTime? date,
    int occurrence = 1,
  }) async {
    controller = TextEditingController(text: text);
    // A phone-width surface: 800 hides overflow a real phone would show.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: TokenTextField(
          controller: controller,
          label: 'Title',
          repeats: repeats,
          date: date ?? DateTime(2026, 10, 5),
          occurrence: occurrence,
          fyStartMonth: 4,
        ),
      ),
    ));
  }

  group('a one-off entry', () {
    testWidgets('is an ordinary field: no button, no helper line', (tester) async {
      await pump(tester, text: 'Rent for August', repeats: false);
      expect(find.byIcon(Icons.data_object), findsNothing);
      expect(find.textContaining('Shows as:'), findsNothing);
      expect(find.textContaining('placeholder'), findsNothing);
    });

    testWidgets('pays nothing in height for a feature it does not use', (tester) async {
      await pump(tester, repeats: false);
      final plain = tester.getSize(find.byType(TextFormField)).height;
      await pump(tester, repeats: true);
      final repeating = tester.getSize(find.byType(TextFormField)).height;
      expect(repeating, greaterThan(plain));
    });
  });

  group('a repeating entry', () {
    testWidgets('offers the picker from inside the field', (tester) async {
      await pump(tester);
      expect(find.byIcon(Icons.data_object), findsOneWidget);
    });

    testWidgets('nudges once, then previews instead', (tester) async {
      await pump(tester, text: 'RD Payment - Aug');
      expect(find.text('Add a placeholder so every repeat dates itself'), findsOneWidget);
      controller.text = 'RD Payment - {MMM}';
      await tester.pump();
      expect(find.textContaining('Add a placeholder'), findsNothing);
      expect(find.text('Shows as: RD Payment - Oct'), findsOneWidget);
    });

    testWidgets('the preview keeps up as you type', (tester) async {
      await pump(tester, text: '{MMM}');
      expect(find.text('Shows as: Oct'), findsOneWidget);
      controller.text = '{MMM} {YYYY}';
      await tester.pump();
      expect(find.text('Shows as: Oct 2026'), findsOneWidget);
    });

    testWidgets('the preview follows the entry date, not today', (tester) async {
      // A due dated December previews December, whatever month it is now.
      await pump(tester, text: 'RD Payment - {MMM} {YYYY}', date: DateTime(2027, 12, 8));
      expect(find.text('Shows as: RD Payment - Dec 2027'), findsOneWidget);
    });

    testWidgets('a date change moves the preview with it', (tester) async {
      await pump(tester, text: '{MMM}', date: DateTime(2026, 10, 5));
      expect(find.text('Shows as: Oct'), findsOneWidget);
      await pump(tester, text: '{MMM}', date: DateTime(2026, 11, 5));
      expect(find.text('Shows as: Nov'), findsOneWidget);
    });

    testWidgets("{#} previews this entry's number in the series", (tester) async {
      await pump(tester, text: 'EMI {#} of 24', occurrence: 7);
      expect(find.text('Shows as: EMI 7 of 24'), findsOneWidget);
    });
  });

  group('the picker', () {
    testWidgets('lists every placeholder with an example from the real date', (tester) async {
      await pump(tester);
      await tester.tap(find.byIcon(Icons.data_object));
      await tester.pumpAndSettle();
      expect(find.text('Placeholders'), findsOneWidget);
      expect(find.text('{MMM}'), findsOneWidget);
      expect(find.text('Oct'), findsOneWidget);
      expect(find.text('{Q}'), findsOneWidget);
      expect(find.text('Q4'), findsOneWidget);
      // The offset syntax is documented where someone would look for it.
      await tester.ensureVisible(find.text('{MMM-1}'));
      await tester.pumpAndSettle();
      expect(find.text('Sept'), findsOneWidget);
    });

    testWidgets('inserts at the caret and closes', (tester) async {
      await pump(tester, text: 'RD Payment - ');
      controller.selection = const TextSelection.collapsed(offset: 3);
      await tester.tap(find.byIcon(Icons.data_object));
      await tester.pumpAndSettle();
      await tester.tap(find.text('{MMM}'));
      await tester.pumpAndSettle();
      expect(find.text('Placeholders'), findsNothing);
      expect(controller.text, 'RD {MMM}Payment - ');
      // The caret follows the insertion, so typing continues where you look.
      expect(controller.selection.baseOffset, 8);
    });

    testWidgets('the preview picks up what the picker inserted', (tester) async {
      await pump(tester, text: 'RD Payment - ');
      await tester.tap(find.byIcon(Icons.data_object));
      await tester.pumpAndSettle();
      await tester.tap(find.text('{MMM}'));
      await tester.pumpAndSettle();
      expect(find.text('Shows as: RD Payment - Oct'), findsOneWidget);
    });
  });
}
