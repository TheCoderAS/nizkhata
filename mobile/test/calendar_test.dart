import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/screens/calendar_screen.dart';

void main() {
  group('calendarMonthForPage', () {
    const initial = 1200;
    final base = DateTime(2026, 8);

    test('the initial page is the base month', () {
      expect(calendarMonthForPage(base, initial, initial), DateTime(2026, 8));
    });

    test('swiping forward and back rolls the year over', () {
      expect(calendarMonthForPage(base, initial + 1, initial), DateTime(2026, 9));
      expect(calendarMonthForPage(base, initial + 5, initial), DateTime(2027, 1));
      expect(calendarMonthForPage(base, initial - 8, initial), DateTime(2025, 12));
      expect(calendarMonthForPage(base, initial - 20, initial), DateTime(2024, 12));
    });

    test('paging is reversible', () {
      for (var delta = -30; delta <= 30; delta++) {
        final m = calendarMonthForPage(base, initial + delta, initial);
        final months = (m.year - base.year) * 12 + (m.month - base.month);
        expect(months, delta);
      }
    });
  });

  group('calendarGridRows', () {
    test('a 28-day month starting on Sunday needs exactly 4 rows', () {
      expect(calendarGridRows(DateTime(2026, 2)), 4);
    });

    test('a 31-day month starting on Saturday needs 6 rows', () {
      expect(calendarGridRows(DateTime(2026, 8)), 6);
      expect(calendarGridRows(DateTime(2027, 5)), 6);
    });

    test('typical months need 5 rows', () {
      expect(calendarGridRows(DateTime(2026, 3)), 5);
      expect(calendarGridRows(DateTime(2026, 11)), 5);
    });

    test('every month of a decade fits in 4 to 6 rows', () {
      for (var y = 2020; y < 2030; y++) {
        for (var m = 1; m <= 12; m++) {
          final rows = calendarGridRows(DateTime(y, m));
          expect(rows, inInclusiveRange(4, 6), reason: 'for $y-$m');
          // The grid must hold every day of the month.
          expect(rows * 7, greaterThanOrEqualTo(DateTime(y, m + 1, 0).day));
        }
      }
    });
  });
}
