import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/widgets/row_actions.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: ListView(children: [child])),
    );

void main() {
  testWidgets('long-press opens the action sheet and taps run the action',
      (tester) async {
    var edited = false;
    var deleted = false;
    await tester.pumpWidget(_wrap(RowActions(
      id: 'r1',
      title: 'Groceries',
      menu: [
        RowAction(icon: Icons.edit, label: 'Edit', onTap: () => edited = true),
        RowAction(
            icon: Icons.delete,
            label: 'Delete',
            destructive: true,
            onTap: () => deleted = true),
      ],
      child: const Card(child: ListTile(title: Text('Row'))),
    )));

    await tester.longPress(find.text('Row'));
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsOneWidget); // sheet header
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(edited, true);
    expect(deleted, false);
    // Sheet closed after choosing.
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('swipe triggers the action and the row springs back',
      (tester) async {
    var paid = false;
    await tester.pumpWidget(_wrap(RowActions(
      id: 'r2',
      swipeStart: RowAction(
          icon: Icons.payments, label: 'Record payment', onTap: () => paid = true),
      menu: [
        RowAction(icon: Icons.payments, label: 'Record payment', onTap: () {}),
      ],
      child: const Card(child: ListTile(title: Text('Due row'))),
    )));

    await tester.drag(find.text('Due row'), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(paid, true);
    // Never dismissed — the row is still there.
    expect(find.text('Due row'), findsOneWidget);
  });

  testWidgets('swipe in an unconfigured direction does nothing',
      (tester) async {
    var triggered = false;
    await tester.pumpWidget(_wrap(RowActions(
      id: 'r3',
      swipeStart: RowAction(
          icon: Icons.payments, label: 'Pay', onTap: () => triggered = true),
      child: const Card(child: ListTile(title: Text('Row'))),
    )));

    await tester.drag(find.text('Row'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(triggered, false);
    expect(find.text('Row'), findsOneWidget);
  });
}
