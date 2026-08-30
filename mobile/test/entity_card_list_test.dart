import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nizkhata/widgets/entity_card_list.dart';

class _Row {
  final String name;
  final double balance;
  const _Row(this.name, this.balance);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpList(
    WidgetTester tester, {
    String? defaultSortKey,
    bool defaultAscending = false,
  }) async {
    const rows = [
      _Row('Axis Bank', 30000.37),
      _Row('Cash Account', 0),
      _Row('SBI Bank', 3901.52),
      _Row('Zeta Bank', 120000),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EntityCardList<_Row>(
          listId: 'test-accounts',
          rows: rows,
          defaultSortKey: defaultSortKey,
          defaultAscending: defaultAscending,
          fields: [
            CardField<_Row>(
              key: 'name',
              label: 'Name',
              role: CardRole.title,
              locked: true,
              sortValue: (r) => r.name.toLowerCase(),
              text: (r) => r.name,
            ),
            CardField<_Row>(
              key: 'balance',
              label: 'Balance',
              role: CardRole.amount,
              sortValue: (r) => r.balance,
              text: (r) => r.balance.toStringAsFixed(2),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  List<String> orderOnScreen(WidgetTester tester, List<String> names) {
    final placed = [
      for (final n in names)
        if (tester.any(find.text(n))) (n, tester.getTopLeft(find.text(n)).dy),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final p in placed) p.$1];
  }

  testWidgets('sorting by balance puts the fullest account first',
      (tester) async {
    await pumpList(tester, defaultSortKey: 'balance');
    expect(
      orderOnScreen(tester, ['Zeta Bank', 'Axis Bank', 'SBI Bank', 'Cash Account']),
      ['Zeta Bank', 'Axis Bank', 'SBI Bank', 'Cash Account'],
    );
  });

  testWidgets('ascending flips it', (tester) async {
    await pumpList(tester, defaultSortKey: 'balance', defaultAscending: true);
    expect(
      orderOnScreen(tester, ['Zeta Bank', 'Axis Bank', 'SBI Bank', 'Cash Account']),
      ['Cash Account', 'SBI Bank', 'Axis Bank', 'Zeta Bank'],
    );
  });

  testWidgets('without a default sort the caller order is kept', (tester) async {
    await pumpList(tester);
    expect(
      orderOnScreen(tester, ['Zeta Bank', 'Axis Bank', 'SBI Bank', 'Cash Account']),
      ['Axis Bank', 'Cash Account', 'SBI Bank', 'Zeta Bank'],
    );
  });

  testWidgets('card padding is symmetric so amounts clear the right edge',
      (tester) async {
    await pumpList(tester, defaultSortKey: 'balance');
    // Measure the gap on screen rather than poking at widget internals: the
    // complaint was the amount sitting against the card's right edge.
    final card = tester.getRect(find.byType(Card).first);
    final amount = tester.getRect(find.text('120000.00'));
    final title = tester.getRect(find.text('Zeta Bank'));
    final gapRight = card.right - amount.right;
    final gapLeft = title.left - card.left;
    expect(gapRight, greaterThanOrEqualTo(12),
        reason: 'the amount sits against the card edge');
    // And it should match the breathing room on the other side.
    expect((gapRight - gapLeft).abs(), lessThanOrEqualTo(2));
  });
}
