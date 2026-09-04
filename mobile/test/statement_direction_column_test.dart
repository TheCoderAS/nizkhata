// A statement that prints one unsigned Amount column and says which way each
// row runs in a column beside it. Extremely common on Indian card statements,
// and it used to import as nothing at all: the header "Debit/Credit" was
// claimed as the debit AMOUNT column, so the real amount was never read.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/services/statement_parser.dart';

void main() {
  final bytes =
      Uint8List.fromList(File('test/fixtures/card_statement_direction_column.csv').readAsBytesSync());
  final grid = parseStatement(bytes, 'transaction_summary.csv');

  group('reading the columns', () {
    late ColumnMapping m;
    setUp(() => m = suggestMapping(grid.header));

    test('takes "Debit/Credit" as the direction, not as an amount', () {
      expect(grid.header[3], 'Debit/Credit');
      expect(m.direction, 3);
      expect(m.debit, isNull);
      expect(m.credit, isNull);
    });

    test('so the real amount column is still found', () {
      expect(grid.header[2], 'Amount (INR)');
      expect(m.amount, 2);
      expect(m.complete, true);
    });

    test('and the date and description land where they should', () {
      expect(m.date, 0);
      expect(m.description, 1);
    });
  });

  group('reading the rows', () {
    late List<ImportRowDraft> rows;
    setUp(() {
      rows = buildImportRows(grid, suggestMapping(grid.header), DateOrder.dmy)
          .where((r) => r.parseable)
          .toList();
    });

    test('every row comes through', () {
      // This is the assertion that matters: the screen said 0 of 0.
      expect(rows.length, 9);
    });

    test('a debit is money out', () {
      final tata = rows.firstWhere((r) => r.description.contains('TataSteel'));
      expect(tata.amount, -49633.00);
      expect(tata.date, DateTime(2026, 8, 20));
    });

    test('a credit is money in', () {
      final received = rows.firstWhere((r) => r.description.contains('BBPS'));
      expect(received.amount, 12175.12);
      expect(received.date, DateTime(2026, 8, 1));
    });

    test('the direction decides the sign, not the printed figure', () {
      // Nothing in the file carries a minus sign, so every row would have
      // come out positive if the direction column were being ignored.
      expect(rows.where((r) => r.amount! < 0).length, 8);
      expect(rows.where((r) => r.amount! > 0).length, 1);
    });

    test('descriptions survive their commas and slashes', () {
      expect(
        rows.any((r) => r.description.contains('moxiesupplypriv78.rzp@icici')),
        true,
      );
    });
  });

  group('what a direction cell can say', () {
    test('reads the words and the abbreviations', () {
      for (final out in ['Debit', 'debit', 'DR', 'dr', 'D', 'W', 'Withdrawal']) {
        expect(isMoneyOutCell(out), true, reason: out);
      }
      for (final into in ['Credit', 'credit', 'CR', 'cr', 'C', 'Deposit']) {
        expect(isMoneyOutCell(into), false, reason: into);
      }
    });

    test('says nothing when the cell says nothing it understands', () {
      // Better to fall back on the amount's own sign than to call every
      // unreadable row money out.
      expect(isMoneyOutCell(''), isNull);
      expect(isMoneyOutCell('   '), isNull);
      expect(isMoneyOutCell('xyz'), isNull);
    });
  });

  group('the date as statements actually print it', () {
    test("reads a shortened year written with an apostrophe", () {
      // The other half of why this file imported as nothing: a row whose date
      // will not parse is dropped, so every row was.
      expect(parseFlexibleDate("20 Aug '26", DateOrder.dmy), DateTime(2026, 8, 20));
      expect(parseFlexibleDate("01 Jan '27", DateOrder.dmy), DateTime(2027, 1, 1));
      expect(parseFlexibleDate("3/4/'26", DateOrder.dmy), DateTime(2026, 4, 3));
    });

    test('still reads the forms it always did', () {
      expect(parseFlexibleDate('20 Aug 2026', DateOrder.dmy), DateTime(2026, 8, 20));
      expect(parseFlexibleDate('20-Aug-26', DateOrder.dmy), DateTime(2026, 8, 20));
      expect(parseFlexibleDate('20/08/2026', DateOrder.dmy), DateTime(2026, 8, 20));
      expect(parseFlexibleDate('08/20/2026', DateOrder.mdy), DateTime(2026, 8, 20));
    });

    test('still refuses what is not a date', () {
      expect(parseFlexibleDate('Transaction Details', DateOrder.dmy), isNull);
      expect(parseFlexibleDate('', DateOrder.dmy), isNull);
      expect(parseFlexibleDate('31 Feb 2026', DateOrder.dmy), isNull);
    });
  });

  test('a plain two-column statement is untouched by any of this', () {
    final two = suggestMapping(['Date', 'Narration', 'Withdrawal', 'Deposit', 'Balance']);
    expect(two.debit, 2);
    expect(two.credit, 3);
    expect(two.direction, isNull);
    expect(two.balance, 4);
  });
}
