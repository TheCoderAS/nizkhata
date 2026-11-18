// Deleting an account: the confirmation that guards it, and the order the
// eraser deletes in, which the Firestore rules depend on.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/core/theme.dart';
import 'package:nizkhata/screens/profile_screen.dart';
import 'package:nizkhata/services/account_eraser.dart';

void main() {
  group('the order of deletion', () {
    test('everyday records go while the workspace and its roles still exist', () {
      for (final col in ['transactions', 'dues', 'debts', 'budgets', 'contacts', 'accounts', 'invites']) {
        expect(kErasedWithWorkspaceAlive, contains(col));
      }
    });

    test('the history, built-in categories and roles go only after the workspace', () {
      expect(kErasedAfterWorkspace, containsAll(['revisions', 'categories', 'roles']));
      expect(kErasedWithWorkspaceAlive.toSet().intersection(kErasedAfterWorkspace.toSet()), isEmpty);
    });

    test('roles go last: the category rule still reads the role', () {
      expect(kErasedAfterWorkspace.last, 'roles');
    });
  });

  group('the confirmation', () {
    Future<List<bool?>> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final results = <bool?>[];
      await tester.pumpWidget(MaterialApp(
        theme: buildDarkTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => results
                  .add(await showDialog<bool>(context: context, builder: (_) => const DeleteAccountDialog())),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    FilledButton deleteButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete account'));

    testWidgets('says what goes, and will not delete until DELETE is typed', (tester) async {
      await open(tester);
      expect(find.textContaining('Every workspace you own'), findsOneWidget);
      expect(deleteButton(tester).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'delet');
      await tester.pump();
      expect(deleteButton(tester).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'delete');
      await tester.pump();
      expect(deleteButton(tester).onPressed, isNotNull);
    });

    testWidgets('confirming answers yes; cancelling answers no', (tester) async {
      var results = await open(tester);
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
      await tester.pumpAndSettle();
      expect(results, [true]);

      results = await open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });
  });
}
