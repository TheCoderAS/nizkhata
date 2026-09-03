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

  Future<void> pump(WidgetTester tester, {String text = ''}) async {
    controller = TextEditingController(text: text);
    // A phone-width surface: the chip strip has to survive 360dp, not 800.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Column(
          children: [
            TextField(controller: controller),
            TokenAssist(
              controller: controller,
              nextDate: DateTime(2026, 10, 5),
              fyStartMonth: 4,
            ),
          ],
        ),
      ),
    ));
  }

  testWidgets('offers the short list of chips plus a way to the rest', (tester) async {
    await pump(tester);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('a chip inserts its placeholder at the caret', (tester) async {
    await pump(tester, text: 'RD Payment - ');
    controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.tap(find.text('Month'));
    await tester.pump();
    expect(controller.text, 'RD {MMM}Payment - ');
    // The caret follows the insertion, so typing continues where you look.
    expect(controller.selection.baseOffset, 8);
  });

  testWidgets('the preview shows what the NEXT entry will read', (tester) async {
    await pump(tester, text: 'RD Payment - {MMM}');
    expect(find.text('Next: RD Payment - Oct'), findsOneWidget);
  });

  testWidgets('the preview appears only once there is a placeholder', (tester) async {
    await pump(tester, text: 'RD Payment - Aug');
    expect(find.textContaining('Next:'), findsNothing);
    controller.text = 'RD Payment - {MMM}';
    await tester.pump();
    expect(find.text('Next: RD Payment - Oct'), findsOneWidget);
  });

  testWidgets('the preview keeps up as you type', (tester) async {
    await pump(tester, text: '{MMM}');
    expect(find.text('Next: Oct'), findsOneWidget);
    controller.text = '{MMM} {YYYY}';
    await tester.pump();
    expect(find.text('Next: Oct 2026'), findsOneWidget);
  });

  testWidgets('"More" lists every placeholder with a live example', (tester) async {
    await pump(tester);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Placeholders'), findsOneWidget);
    expect(find.text('{Q}'), findsOneWidget);
    // Examples are rendered from the real date, so they cannot go stale.
    expect(find.text('Q4'), findsOneWidget);
    // The offset syntax is documented where someone will look for it.
    await tester.ensureVisible(find.text('{MMM-1}'));
    await tester.pumpAndSettle();
    expect(find.text('{MMM-1}'), findsOneWidget);
    expect(find.text('Sept'), findsOneWidget);
  });

  testWidgets('picking from "More" inserts it and closes the sheet', (tester) async {
    await pump(tester, text: 'Tax ');
    controller.selection = const TextSelection.collapsed(offset: 4);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    // The list is longer than the sheet, so scroll to what we came for.
    await tester.ensureVisible(find.text('{Q}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('{Q}'));
    await tester.pumpAndSettle();
    expect(find.text('Placeholders'), findsNothing);
    expect(controller.text, 'Tax {Q}');
  });
}
