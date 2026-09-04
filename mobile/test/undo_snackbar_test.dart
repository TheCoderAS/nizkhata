// The Undo bar after a delete. Flutter defaults SnackBar.persist to
// `action != null`, so adding the Undo button silently made this bar
// permanent: the six second duration it was given was never applied.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/core/theme.dart';

/// The bar exactly as deleteWithUndo builds it.
SnackBar undoBar({required VoidCallback onUndo}) => SnackBar(
      content: const Text('Due deleted'),
      duration: const Duration(seconds: 6),
      persist: false,
      showCloseIcon: true,
      action: SnackBarAction(label: 'Undo', onPressed: onUndo),
    );

void main() {
  Future<void> show(WidgetTester tester, SnackBar bar) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => ScaffoldMessenger.of(c).showSnackBar(bar),
            child: const Text('delete'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();
  }

  /// Steps a second at a time, the way time actually passes, and reports how
  /// long the bar stayed. Null means it outlasted the wait.
  Future<int?> secondsUntilGone(WidgetTester tester, {int wait = 12}) async {
    for (var i = 1; i <= wait; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.text('Due deleted').evaluate().isEmpty) return i;
    }
    return null;
  }

  testWidgets('goes away on its own', (tester) async {
    await show(tester, undoBar(onUndo: () {}));
    expect(find.text('Due deleted'), findsOneWidget);
    final gone = await secondsUntilGone(tester);
    expect(gone, isNotNull, reason: 'the bar never timed out');
    expect(gone, lessThanOrEqualTo(8));
  });

  testWidgets('a bar with an action would otherwise stay forever', (tester) async {
    // The bug, held in place: the same bar without persist:false. If Flutter
    // ever changes this default, this test fails and the fix can go.
    await show(
      tester,
      SnackBar(
        content: const Text('Due deleted'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
      ),
    );
    expect(await secondsUntilGone(tester), isNull);
  });

  testWidgets('offers a close button, so it can be dismissed by tapping', (tester) async {
    await show(tester, undoBar(onUndo: () {}));
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Due deleted'), findsNothing);
  });

  testWidgets('Undo still works, and closes the bar', (tester) async {
    var undone = false;
    await show(tester, undoBar(onUndo: () => undone = true));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, true);
    expect(find.text('Due deleted'), findsNothing);
  });
}
