import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/widgets/discard_guard.dart';

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required bool dirty,
    // Guarded sheets are opened with dragging OFF; see the swipe tests below.
    bool enableDrag = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                enableDrag: enableDrag,
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

  group('close button', () {
    testWidgets('closes a clean form', (tester) async {
      await pumpSheet(tester, dirty: false);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('sheet body'), findsNothing);
    });

    testWidgets('asks on a dirty form', (tester) async {
      await pumpSheet(tester, dirty: true);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('sheet body'), findsOneWidget);
    });
  });

  group('sticky header', () {
    testWidgets('the first field clears the header, label and all',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  enableDrag: false,
                  builder: (_) => DiscardGuard(
                    title: 'New due',
                    isDirty: () => false,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: 'Title',
                          // The state that gets clipped: label floated up onto
                          // the outline, which is where it lands once the field
                          // is focused or filled.
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                      ),
                    ),
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

      // Measured from the header's own box, not the title's text baseline:
      // the box edge is where the form gets clipped. Pinned to a literal so
      // the assertion still bites if kSheetHeaderGap is set to zero.
      final headerBottom = tester.getRect(find.byType(AnimatedContainer)).bottom;
      final fieldTop = tester.getTopLeft(find.byType(TextField)).dy;
      expect(fieldTop - headerBottom, greaterThanOrEqualTo(8.0));
    });

    Color? headerBorderColor(WidgetTester tester) {
      final box = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      final border = (box.decoration as BoxDecoration).border as Border;
      return border.bottom.color;
    }

    testWidgets('divider appears only once the form scrolls under it',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  enableDrag: false,
                  builder: (_) => SizedBox(
                    height: 400,
                    child: DiscardGuard(
                      title: 'Edit due',
                      isDirty: () => false,
                      child: ListView(
                        children: [
                          for (var i = 0; i < 30; i++)
                            SizedBox(height: 48, child: Text('field $i')),
                        ],
                      ),
                    ),
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

      expect(find.text('Edit due'), findsOneWidget);
      expect(headerBorderColor(tester), Colors.transparent);

      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(headerBorderColor(tester), isNot(Colors.transparent));

      // Back to the top and the line goes away again.
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(headerBorderColor(tester), Colors.transparent);
    });
  });

  group('swipe down', () {
    testWidgets('cannot throw away a dirty form when dragging is off',
        (tester) async {
      await pumpSheet(tester, dirty: true);
      await tester.drag(find.text('sheet body'), const Offset(0, 400));
      await tester.pumpAndSettle();
      // The edits are still there, and nothing had to be confirmed.
      expect(find.text('sheet body'), findsOneWidget);
      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('WOULD bypass the guard if dragging were enabled', (tester) async {
      // Documents why guarded sheets pass enableDrag: false. Flutter's bottom
      // sheet pops the route directly when a drag closes it, so PopScope never
      // runs and the edits vanish. If this test ever fails because the sheet
      // stayed open, Flutter has started routing drag-close through
      // Navigator.maybePop and guarded sheets can take their drag handle back.
      await pumpSheet(tester, dirty: true, enableDrag: true);
      await tester.drag(find.text('sheet body'), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('sheet body'), findsNothing);
      expect(find.text('Discard changes?'), findsNothing);
    });
  });
}
