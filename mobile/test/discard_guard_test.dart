import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/widgets/discard_guard.dart';

void main() {
  Future<void> pumpSheet(WidgetTester tester, {required bool dirty}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => DiscardGuard(
                  isDirty: () => dirty,
                  child: const SizedBox(height: 220, child: Text('sheet body')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('sheet body'), findsOneWidget);
  }

  testWidgets('clean form closes freely on back', (tester) async {
    await pumpSheet(tester, dirty: false);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('sheet body'), findsNothing);
    expect(find.text('Discard changes?'), findsNothing);
  });

  testWidgets('dirty form asks before discarding; Keep editing stays', (tester) async {
    await pumpSheet(tester, dirty: true);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('sheet body'), findsOneWidget); // still open

    await nav.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('sheet body'), findsNothing); // discarded
  });
}
