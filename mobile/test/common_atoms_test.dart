import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/core/theme.dart';
import 'package:nizkhata/widgets/common.dart';

Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(theme: buildDarkTheme(), home: Scaffold(body: child)),
    );

void main() {
  testWidgets('SectionLabel shouts its heading in caps', (tester) async {
    await pump(tester, const SectionLabel('Amount & notes'));
    expect(find.text('AMOUNT & NOTES'), findsOneWidget);
  });

  testWidgets('DetailRow lines its values up in a fixed label column',
      (tester) async {
    await pump(
      tester,
      const Column(
        children: [
          DetailRow('Contact', 'Sonali'),
          DetailRow('A much longer label', 'Kumari'),
        ],
      ),
    );
    // Both values start at the same x, which is the point of the column.
    expect(tester.getTopLeft(find.text('Sonali')).dx,
        tester.getTopLeft(find.text('Kumari')).dx);
  });

  testWidgets('RemovableChip clears the filter it stands for', (tester) async {
    var cleared = false;
    await pump(tester, RemovableChip('Status: Open', () => cleared = true));
    expect(find.text('Status: Open'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(cleared, true);
  });

  group('SearchField', () {
    testWidgets('reports what is typed', (tester) async {
      String? typed;
      await pump(tester, SearchField(hint: 'Search dues…', onChanged: (v) => typed = v));
      expect(find.text('Search dues…'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'rent');
      expect(typed, 'rent');
    });

    testWidgets('offers a clear button once there is text, on every screen',
        (tester) async {
      String? typed;
      await pump(tester, SearchField(hint: 'Search…', onChanged: (v) => typed = v));
      // Nothing to clear yet.
      expect(find.byIcon(Icons.close), findsNothing);

      await tester.enterText(find.byType(TextField), 'rent');
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(typed, '');
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });
}
