import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/data/models.dart';
import 'package:nizkhata/data/settle_up.dart';
import 'package:nizkhata/services/recurrence.dart';

Due _due(String id, DateTime dueDate, String status,
        {String? recurrence, String? seriesId}) =>
    Due(
      id: id,
      workspaceId: 'ws',
      direction: 'payable',
      title: 'RD',
      amount: 5000,
      dueDate: dueDate,
      status: status,
      recurrence: recurrence,
      recurrenceId: seriesId,
    );

void main() {
  group('nextOccurrence', () {
    test('monthly clamps month-end overflow', () {
      expect(nextOccurrence(DateTime(2026, 1, 31), 'monthly'), DateTime(2026, 2, 28));
      expect(nextOccurrence(DateTime(2026, 8, 31), 'monthly'), DateTime(2026, 9, 30));
      expect(nextOccurrence(DateTime(2026, 12, 15), 'monthly'), DateTime(2027, 1, 15));
    });
    test('weekly and yearly', () {
      expect(nextOccurrence(DateTime(2026, 8, 31), 'weekly'), DateTime(2026, 9, 7));
      expect(nextOccurrence(DateTime(2024, 2, 29), 'yearly'), DateTime(2025, 2, 28));
    });
  });

  group('missingDueInstances', () {
    final now = DateTime(2026, 9, 2);

    test('settled recurring due spawns exactly one next instance', () {
      final dues = [_due('d1', DateTime(2026, 8, 31), 'settled', recurrence: 'monthly')];
      final missing = missingDueInstances(dues, now);
      expect(missing.length, 1);
      expect(missing.single.dueDate, DateTime(2026, 9, 30));
      expect(missing.single.id, 'rec_d1_20260930');
    });

    test('idempotent: existing instance id suppresses re-creation', () {
      final dues = [
        _due('d1', DateTime(2026, 8, 31), 'settled', recurrence: 'monthly'),
        _due('rec_d1_20260930', DateTime(2026, 9, 30), 'open',
            recurrence: 'monthly', seriesId: 'd1'),
      ];
      expect(missingDueInstances(dues, now), isEmpty);
    });

    test('only the latest instance of a series spawns', () {
      final dues = [
        _due('d1', DateTime(2026, 7, 31), 'settled', recurrence: 'monthly'),
        _due('rec_d1_20260831', DateTime(2026, 8, 31), 'settled',
            recurrence: 'monthly', seriesId: 'd1'),
      ];
      final missing = missingDueInstances(dues, now);
      expect(missing.length, 1);
      expect(missing.single.id, 'rec_d1_20260930'); // from the Aug instance only
    });

    test('open future due does not spawn; open past-due does', () {
      expect(
          missingDueInstances(
              [_due('d1', DateTime(2026, 9, 30), 'open', recurrence: 'monthly')], now),
          isEmpty);
      final past = missingDueInstances(
          [_due('d1', DateTime(2026, 8, 31), 'open', recurrence: 'monthly')], now);
      expect(past.length, 1);
    });

    test('non-recurring dues never spawn', () {
      expect(missingDueInstances([_due('d1', DateTime(2026, 8, 1), 'settled')], now), isEmpty);
    });
  });

  group('recurringTxnSuggestions', () {
    Txn txn(String id, DateTime date, {String? recurrence, String note = 'Salary'}) => Txn(
          id: id,
          workspaceId: 'ws',
          date: date,
          accountId: 'acc',
          totalAmount: 50000,
          hasSplit: false,
          financialYear: '2026-27',
          lines: [TxnLine(lineId: 'l', type: 'income', amount: 50000)],
          note: note,
          recurrence: recurrence,
        );

    test('suggests when the next occurrence has arrived, using the newest of a series', () {
      final now = DateTime(2026, 9, 2);
      final s = recurringTxnSuggestions([
        txn('t1', DateTime(2026, 7, 1), recurrence: 'monthly'),
        txn('t2', DateTime(2026, 8, 1), recurrence: 'monthly'),
      ], now);
      expect(s.length, 1);
      expect(s.single.nextDate, DateTime(2026, 9, 1));
    });

    test('quiet before the date arrives', () {
      final s = recurringTxnSuggestions(
          [txn('t1', DateTime(2026, 9, 1), recurrence: 'monthly')], DateTime(2026, 9, 2));
      expect(s, isEmpty);
    });
  });

  group('buildSettleUpPlan', () {
    test('nets open debts both directions into repayment lines', () {
      final debts = [
        Debt(
            id: 'owed1',
            workspaceId: 'ws',
            contactId: 'c1',
            direction: 'owed',
            purpose: 'lending',
            principal: 10000,
            status: 'open'),
        Debt(
            id: 'owe1',
            workspaceId: 'ws',
            contactId: 'c1',
            direction: 'owe',
            purpose: 'loan',
            principal: 4000,
            status: 'open'),
        Debt(
            id: 'other',
            workspaceId: 'ws',
            contactId: 'c2',
            direction: 'owed',
            purpose: 'loan',
            principal: 999,
            status: 'open'),
      ];
      // Establishing lines so outstanding is non-zero.
      final txns = [
        Txn(
            id: 'e1',
            workspaceId: 'ws',
            date: DateTime(2026, 1, 1),
            accountId: 'a',
            totalAmount: -10000,
            hasSplit: false,
            financialYear: '2025-26',
            lines: [TxnLine(lineId: 'l1', type: 'lend', amount: 10000, debtId: 'owed1')]),
        Txn(
            id: 'e2',
            workspaceId: 'ws',
            date: DateTime(2026, 1, 2),
            accountId: 'a',
            totalAmount: 4000,
            hasSplit: false,
            financialYear: '2025-26',
            lines: [TxnLine(lineId: 'l2', type: 'borrow', amount: 4000, debtId: 'owe1')]),
      ];
      final plan = buildSettleUpPlan('c1', debts, txns, lineIdSeed: 1);
      expect(plan.lines.length, 2);
      expect(plan.debts.map((d) => d.id).toSet(), {'owed1', 'owe1'});
      // They owe 10,000, you owe 4,000 → you collect net 6,000.
      expect(plan.signedTotal, 6000.0);
    });

    test('empty when nothing outstanding', () {
      expect(buildSettleUpPlan('c1', const [], const [], lineIdSeed: 1).isEmpty, true);
    });
  });
}
