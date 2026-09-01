import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/data/derive.dart';
import 'package:nizkhata/data/models.dart';

Due _due(String id, DateTime date, {String status = 'open', double amount = 1000}) => Due(
      id: id,
      workspaceId: 'ws',
      direction: 'payable',
      title: id,
      amount: amount,
      dueDate: date,
      status: status,
    );

void main() {
  final day = DateTime(2026, 9, 3);

  test('counts only the dues a day view will list', () {
    // Six dues on the day, but five are done with: the sheet used to promise
    // six and the screen then showed one. Note a due counts as settled when
    // its payments cover it, which is how settleDue records one — the stored
    // status flag only matters for 'cancelled'.
    final dues = [
      _due('open1', day),
      _due('settled1', day, status: 'settled', amount: 1000),
      _due('settled2', day, status: 'settled', amount: 2000),
      _due('cancelled1', day, status: 'cancelled'),
      _due('cancelled2', day, status: 'cancelled'),
      _due('paid-off', day, amount: 500),
      _due('other-day', DateTime(2026, 9, 4)),
    ];
    double settledOf(String id) => switch (id) {
          'settled1' => 1000,
          'settled2' => 2000,
          'paid-off' => 500,
          _ => 0,
        };

    final shown = duesOnDay(dues, day, settledOf);
    expect(shown.map((d) => d.id), ['open1']);
  });

  test('a partly paid due still counts', () {
    final dues = [_due('partial', day, amount: 1000)];
    expect(duesOnDay(dues, day, (_) => 400).length, 1);
  });

  test('dues on other days are excluded', () {
    final dues = [
      _due('a', DateTime(2026, 9, 2)),
      _due('b', DateTime(2026, 10, 3)),
      _due('c', DateTime(2025, 9, 3)),
    ];
    expect(duesOnDay(dues, day, (_) => 0), isEmpty);
  });
}
