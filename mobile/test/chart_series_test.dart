import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/data/derive.dart';
import 'package:nizkhata/data/models.dart';

Account _account(String id, double opening) => Account(
      id: id,
      workspaceId: 'ws',
      name: id,
      type: 'bank',
      openingBalance: opening,
    );

Txn _txn(String id, DateTime date, double amount, String type) => Txn(
      id: id,
      workspaceId: 'ws',
      date: date,
      accountId: 'a1',
      totalAmount: amount,
      hasSplit: false,
      financialYear: '2026-27',
      lines: [TxnLine(lineId: 'l1', type: type, amount: amount.abs())],
    );

void main() {
  // A financial year running Apr 2026 -> Mar 2027, viewed in August 2026.
  final fyStart = DateTime(2026, 4, 1);
  final fyEnd = DateTime(2027, 4, 1);
  final august = DateTime(2026, 8, 15);

  group('net worth series', () {
    test('stops at the current month instead of flatlining to March',
        (() {
      final points = netWorthSeries(
        [_account('a1', 100000)],
        const [],
        [_txn('t1', DateTime(2026, 5, 10), 20000, 'income')],
        fyStart,
        fyEnd,
        now: august,
      );
      // Apr, May, Jun, Jul, Aug — and nothing for Sep..Mar.
      expect(points.map((p) => p.label), ['Apr', 'May', 'Jun', 'Jul', 'Aug']);
    }));

    test('a finished year still plots all twelve months', () {
      final points = netWorthSeries(
        [_account('a1', 100000)],
        const [],
        const [],
        DateTime(2024, 4, 1),
        DateTime(2025, 4, 1),
        now: august,
      );
      expect(points.length, 12);
    });

    test('the plotted months carry the running balance, not zero', () {
      final points = netWorthSeries(
        [_account('a1', 100000)],
        const [],
        [_txn('t1', DateTime(2026, 5, 10), 20000, 'income')],
        fyStart,
        fyEnd,
        now: august,
      );
      expect(points.first.netWorth, 100000);
      expect(points.last.netWorth, 120000);
      // Nothing collapses to zero mid-series, which is what the flat tail
      // looked like on screen.
      expect(points.every((p) => p.netWorth > 0), true);
    });
  });

  group('income vs expense series', () {
    test('stops at the current month rather than drawing zero months', () {
      final trend = trendSeries(
        [
          _txn('t1', DateTime(2026, 5, 10), 20000, 'income'),
          _txn('t2', DateTime(2026, 6, 10), 5000, 'expense'),
        ],
        fyStart,
        fyEnd,
        now: august,
      );
      expect(trend.buckets.map((b) => b.label), ['Apr', 'May', 'Jun', 'Jul', 'Aug']);
      // The totals are unaffected by the truncation.
      expect(trend.income, 20000);
      expect(trend.expense, 5000);
    });

    test('a finished year keeps every month', () {
      final trend = trendSeries(
        const [],
        DateTime(2024, 4, 1),
        DateTime(2025, 4, 1),
        now: august,
      );
      expect(trend.buckets.length, 12);
    });
  });
}
