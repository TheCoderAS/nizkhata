// Statements from outside India: US files (month-first dates, "$1,234.56",
// negatives in parentheses) and European ones (';' between fields, "1.234,56 €",
// day.month.year). The European case is the dangerous one: reading its
// amounts with a '.' decimal mark does not fail, it quietly turns 1.234,56
// into 1.23456 and imports it.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/services/statement_parser.dart';

StatementGrid _fixture(String name) =>
    parseStatement(Uint8List.fromList(File('test/fixtures/$name').readAsBytesSync()), name);

void main() {
  group('a European statement', () {
    final grid = _fixture('statement_eu.csv');
    final m = suggestMapping(grid.header);

    test('splits on ";" even though "," appears as often', () {
      expect(grid.header, ['Date', 'Description', 'Amount', 'Balance']);
      expect(grid.dataRows.first, ['02.01.2026', 'Rewe Markt, Berlin', '-12,50 €', '2.487,50 €']);
    });

    test('is read with a decimal comma', () {
      expect(detectMappingDecimalSeparator(grid.dataRows, m), ',');
    });

    // Uses only what the parser offered before decimal marks existed, so it
    // also runs against the old parser, where it fails: 1.234,56 came out
    // as 1.23456.
    test('every row imports with the exact amount, sign and date', () {
      final order = detectDateOrder(grid.dataRows.map((r) => r[m.date!]));
      expect(order, DateOrder.dmy);
      final rows = buildImportRows(grid, m, order);
      expect(rows.every((r) => r.parseable), true);
      expect([for (final r in rows) r.amount], [-12.50, 1234.56, -1100.00, -89.90, 45.00, -1000.00, 0.07]);
      expect(
          [for (final r in rows) r.balance], [2487.50, 3722.06, 2622.06, 2532.16, 2577.16, 1577.16, 1577.23]);
      expect([
        for (final r in rows) r.date
      ], [
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 9),
        DateTime(2026, 1, 13),
        DateTime(2026, 1, 20),
        DateTime(2026, 1, 28),
        DateTime(2026, 2, 3),
      ]);
    });

    // Without a currency sign nothing looked wrong to the old parser, so it
    // read every figure: 1.234,56 as 1.23456, and 12,50 as 1250.
    test('bare figures are not misread', () {
      final bare = StatementGrid(kind: StatementKind.csv, headerRow: 0, rows: [
        ['Date', 'Description', 'Amount'],
        ['02.01.2026', 'Gehalt', '1.234,56'],
        ['05.01.2026', 'Rewe', '-12,50'],
        ['09.01.2026', 'Miete', '-1.100,00'],
      ]);
      final rows = buildImportRows(bare, suggestMapping(bare.header), DateOrder.dmy);
      expect([for (final r in rows) r.amount], [1234.56, -12.50, -1100.00]);
    });

    test('a decimal mark chosen by hand is honoured', () {
      final forced = suggestMapping(grid.header)..decimalSeparator = '.';
      final rows = buildImportRows(grid, forced, DateOrder.dmy);
      // Read the wrong way, a figure with cents is refused rather than
      // misread. Only "-1.000", which is a valid figure either way, reads
      // (as 1), which is why the screen shows the mark and lets it be changed.
      expect([for (final r in rows) r.amount], [null, null, null, null, null, -1.0, null]);
    });
  });

  group('a US statement', () {
    final grid = _fixture('statement_us.csv');
    final m = suggestMapping(grid.header);

    test('keeps the decimal point', () {
      expect(detectMappingDecimalSeparator(grid.dataRows, m), '.');
    });

    test('every row imports with the exact amount, sign and date', () {
      final order = detectDateOrder(grid.dataRows.map((r) => r[m.date!]));
      expect(order, DateOrder.mdy);
      final rows = buildImportRows(grid, m, order);
      expect(rows.every((r) => r.parseable), true);
      expect([for (final r in rows) r.amount], [-4.75, 1234.56, -45.00, -1800.00, -62.10, 129.99, -200.00]);
      expect(rows.first.balance, 2095.25);
      expect([
        for (final r in rows) r.date
      ], [
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 9),
        DateTime(2026, 1, 13),
        DateTime(2026, 1, 20),
        DateTime(2026, 1, 28),
        DateTime(2026, 2, 3),
      ]);
    });
  });

  group('the Indian statement still reads as before', () {
    test('decimal point, same rows', () {
      final grid = _fixture('card_statement_direction_column.csv');
      final m = suggestMapping(grid.header);
      expect(detectMappingDecimalSeparator(grid.dataRows, m), '.');
      final rows = buildImportRows(grid, m, DateOrder.dmy).where((r) => r.parseable).toList();
      expect(rows.length, 9);
      expect(rows.first.amount, -49633.00);
    });
  });

  group('detectDecimalSeparator', () {
    test('both marks: the last one is the decimal', () {
      expect(detectDecimalSeparator(['1.234,56']), ',');
      expect(detectDecimalSeparator(['1,234.56']), '.');
      expect(detectDecimalSeparator(['1,23,456.78']), '.');
    });

    test('a repeated mark is grouping', () {
      expect(detectDecimalSeparator(['1.234.567']), ',');
      expect(detectDecimalSeparator(['1,234,567']), '.');
    });

    test('a lone mark with one or two decimals is the decimal', () {
      expect(detectDecimalSeparator(['12,50 €']), ',');
      expect(detectDecimalSeparator(['12.5']), '.');
    });

    test('"1,234" alone does not flip the file to a decimal comma', () {
      expect(detectDecimalSeparator(['1,234']), '.');
      expect(detectDecimalSeparator(['1.234']), '.');
      expect(detectDecimalSeparator(['1,234', '2,000', '']), '.');
      // ...but the rest of the column can settle it.
      expect(detectDecimalSeparator(['1.234', '12,50']), ',');
    });

    test('nothing to go on, or a tie, keeps the point', () {
      expect(detectDecimalSeparator(['100', '', 'n/a']), '.');
      expect(detectDecimalSeparator([]), '.');
      expect(detectDecimalSeparator(['12,50', '12.50']), '.');
    });
  });

  group('parseAmountText', () {
    test('honours a decimal comma', () {
      expect(parseAmountText('1.234,56', decimalSeparator: ','), 1234.56);
      expect(parseAmountText('-1.234,56 €', decimalSeparator: ','), -1234.56);
      expect(parseAmountText('1.234,56-', decimalSeparator: ','), -1234.56);
      expect(parseAmountText('1 234,56', decimalSeparator: ','), 1234.56);
      expect(parseAmountText('1 234,56', decimalSeparator: ','), 1234.56);
      expect(parseAmountText('1.000', decimalSeparator: ','), 1000);
    });

    test('refuses the other mark\'s decimals instead of misreading them', () {
      expect(parseAmountText('12,50'), isNull);
      expect(parseAmountText('12.50', decimalSeparator: ','), isNull);
    });

    test('strips currency symbols and codes', () {
      expect(parseAmountText('\$1,234.56'), 1234.56);
      expect(parseAmountText('-\$45.00'), -45.00);
      expect(parseAmountText('(\$45.00)'), -45.00);
      expect(parseAmountText('£99.99'), 99.99);
      expect(parseAmountText('¥1,200'), 1200);
      expect(parseAmountText('₹ 1,000'), 1000);
      expect(parseAmountText('USD 12.00'), 12.00);
      expect(parseAmountText('AED 1,500.25'), 1500.25);
      expect(parseAmountText('12.00 usd'), 12.00);
      expect(parseAmountText('S\$20.00'), 20.00);
      expect(parseAmountText('45,00 €', decimalSeparator: ','), 45.00);
      expect(parseAmountText("CHF 1'234.50"), 1234.50);
      expect(parseAmountText('−45.00'), -45.00);
    });

    test('words that start like a currency code are not amounts', () {
      expect(parseAmountText('UPI/509'), isNull);
      expect(parseAmountText('USDT 5'), isNull);
    });
  });

  group('date order', () {
    test('follows the phone only when the dates cannot say', () {
      expect(dateOrderForLocale('en_US'), DateOrder.mdy);
      expect(dateOrderForLocale('en_GB'), DateOrder.dmy);
      expect(dateOrderForLocale('en_IN'), DateOrder.dmy);
      final ambiguous = ['01/02/2026', '03/04/2026'];
      expect(detectDateOrder(ambiguous, prefer: DateOrder.mdy), DateOrder.mdy);
      expect(detectDateOrder(ambiguous), DateOrder.dmy);
      // A US phone does not override a file that is plainly day-first.
      expect(detectDateOrder(['13/01/2026', '02/01/2026'], prefer: DateOrder.mdy), DateOrder.dmy);
    });
  });

  group('delimiter detection', () {
    test('";" wins over commas that come and go with the data', () {
      final rows = parseDelimitedText('Date;Description;Amount\n'
          '02.01.2026;Rewe, Berlin, Mitte;-12,50\n'
          '03.01.2026;Aldi, Hamburg, Nord;-7,25\n');
      expect(rows[1], ['02.01.2026', 'Rewe, Berlin, Mitte', '-12,50']);
    });
  });
}
