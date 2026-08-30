import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/widgets/row_actions.dart';

void main() {
  testWidgets('every action stays reachable in a long menu', (tester) async {
    // A due row offers seven actions. Without isScrollControlled the sheet is
    // capped at 9/16 of the screen, so the last one is clipped off the bottom
    // and cannot be tapped.
    var deleted = false;
    final labels = [
      'Record payment',
      'Send reminder',
      'View contact',
      'View transactions',
      'Edit',
      'Cancel due',
      'Delete',
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            RowActions(
              id: 'due-1',
              title: 'Partner RD - Aug',
              menu: [
                for (final l in labels)
                  RowAction(
                    icon: Icons.circle,
                    label: l,
                    destructive: l == 'Delete',
                    onTap: () {
                      if (l == 'Delete') deleted = true;
                    },
                  ),
              ],
              child: const Card(child: ListTile(title: Text('Partner RD - Aug'))),
            ),
          ],
        ),
      ),
    ));

    await tester.longPress(find.text('Partner RD - Aug').first);
    await tester.pumpAndSettle();

    // The last action must be on screen and actually tappable.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, true, reason: 'the last action was not reachable');
  });
}
