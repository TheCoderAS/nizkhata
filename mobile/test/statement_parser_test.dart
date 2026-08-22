import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nizkhata/services/statement_parser.dart';

void main() {
  group('parseDelimitedText', () {
    test('parses comma CSV with quoted fields', () {
      final rows = parseDelimitedText(
          'Date,Description,Amount\n01/04/2025,"UPI, Grocery Mart",-450.00\n');
      expect(rows.length, 2);
      expect(rows[1], ['01/04/2025', 'UPI, Grocery Mart', '-450.00']);
    });

    test('auto-detects tab and semicolon delimiters', () {
      final tabbed = parseDelimitedText('Date\tAmount\n01/04/2025\t100\n');
      expect(tabbed[0], ['Date', 'Amount']);
      final semi = parseDelimitedText('Date;Amount\n01/04/2025;100\n');
      expect(semi[1], ['01/04/2025', '100']);
    });

    test('drops empty rows and pads ragged ones', () {
      final rows = parseDelimitedText('a,b,c\n\n1,2\n');
      expect(rows.length, 2);
      expect(rows[1], ['1', '2', '']);
    });
  });

  group('header detection', () {
    test('finds the header row after bank preamble', () {
      final rows = [
        ['HDFC BANK LTD', '', '', '', ''],
        ['Statement for account ****1234', '', '', '', ''],
        ['', '', '', '', ''],
        ['Date', 'Narration', 'Chq./Ref.No.', 'Withdrawal Amt.', 'Deposit Amt.'],
        ['01/04/25', 'UPI-GROCERY', 'UPI/509', '450.00', ''],
      ].where((r) => r.any((c) => c.isNotEmpty)).toList();
      expect(detectHeaderRow(rows), 2);
    });

    test('scores keyword groups distinctly', () {
      expect(headerScore(['Date', 'Narration', 'Debit', 'Credit', 'Balance']), 5);
      expect(headerScore(['random', 'words']), 0);
    });
  });

  group('suggestMapping', () {
    test('maps HDFC-style headers (split debit/credit)', () {
      final m = suggestMapping(
          ['Date', 'Narration', 'Chq./Ref.No.', 'Value Dt', 'Withdrawal Amt.', 'Deposit Amt.', 'Closing Balance']);
      expect(m.date, 0);
      expect(m.description, 1);
      expect(m.reference, 2);
      expect(m.debit, 4);
      expect(m.credit, 5);
      expect(m.splitAmounts, true);
      expect(m.complete, true);
    });

    test('maps SBI-style headers', () {
      final m = suggestMapping(
          ['Txn Date', 'Value Date', 'Description', 'Ref No./Cheque No.', 'Debit', 'Credit', 'Balance']);
      expect(m.date, 0);
      expect(m.description, 2);
      expect(m.debit, 4);
      expect(m.credit, 5);
    });

    test('maps single-amount statements, skipping balance', () {
      final m = suggestMapping(['Date', 'Description', 'Amount', 'Balance Amount']);
      expect(m.amount, 2);
      expect(m.splitAmounts, false);
      expect(m.complete, true);
    });

    test('falls back to a value-date column when no plain date exists', () {
      final m = suggestMapping(['Value Date', 'Particulars', 'Amount']);
      expect(m.date, 0);
    });
  });

  group('parseFlexibleDate', () {
    test('day-first, month-first and year-first numeric', () {
      expect(parseFlexibleDate('01/04/2025', DateOrder.dmy), DateTime(2025, 4, 1));
      expect(parseFlexibleDate('01/04/2025', DateOrder.mdy), DateTime(2025, 1, 4));
      expect(parseFlexibleDate('2025-04-01', DateOrder.dmy), DateTime(2025, 4, 1));
    });

    test('month names and 2-digit years', () {
      expect(parseFlexibleDate('03 Jan 2025', DateOrder.dmy), DateTime(2025, 1, 3));
      expect(parseFlexibleDate('03-JAN-25', DateOrder.dmy), DateTime(2025, 1, 3));
      expect(parseFlexibleDate('Jan 3, 2025', DateOrder.dmy), DateTime(2025, 1, 3));
      expect(parseFlexibleDate('01/04/25', DateOrder.dmy), DateTime(2025, 4, 1));
    });

    test('rejects impossible dates and garbage', () {
      expect(parseFlexibleDate('31/02/2025', DateOrder.dmy), isNull);
      expect(parseFlexibleDate('UPI-GROCERY', DateOrder.dmy), isNull);
      expect(parseFlexibleDate('', DateOrder.dmy), isNull);
    });

    test('detectDateOrder disambiguates via day > 12', () {
      expect(detectDateOrder(['13/01/2025', '14/01/2025']), DateOrder.dmy);
      expect(detectDateOrder(['01/13/2025', '01/14/2025']), DateOrder.mdy);
      // Ambiguous samples prefer day-first.
      expect(detectDateOrder(['01/02/2025', '03/04/2025']), DateOrder.dmy);
      expect(detectDateOrder(['2025-04-01']), DateOrder.dmy); // ymd parses under any order
    });
  });

  group('parseAmountText', () {
    test('handles Indian formats', () {
      expect(parseAmountText('1,23,456.78'), 123456.78);
      expect(parseAmountText('₹ 1,000'), 1000);
      expect(parseAmountText('Rs.250'), 250);
      expect(parseAmountText('INR 99.50'), 99.50);
    });

    test('sign markers', () {
      expect(parseAmountText('500.00 Dr'), -500.00);
      expect(parseAmountText('500.00 CR'), 500.00);
      expect(parseAmountText('(750)'), -750);
      expect(parseAmountText('-42.5'), -42.5);
      expect(parseAmountText('+42.5'), 42.5);
    });

    test('non-numeric returns null', () {
      expect(parseAmountText(''), isNull);
      expect(parseAmountText('-'), isNull);
      expect(parseAmountText('UPI/509'), isNull);
    });
  });

  group('buildImportRows', () {
    StatementGrid grid(List<List<String>> rows) =>
        StatementGrid(kind: StatementKind.csv, rows: rows, headerRow: 0);

    test('debit/credit mode signs amounts correctly', () {
      final g = grid([
        ['Date', 'Narration', 'Withdrawal', 'Deposit'],
        ['01/04/2025', 'Grocery', '450.00', ''],
        ['02/04/2025', 'Salary', '', '50,000.00'],
      ]);
      final rows = buildImportRows(g, suggestMapping(g.header), DateOrder.dmy);
      expect(rows.length, 2);
      expect(rows[0].amount, -450.00);
      expect(rows[1].amount, 50000.00);
      expect(rows[0].date, DateTime(2025, 4, 1));
      expect(rows.every((r) => r.parseable), true);
    });

    test('single signed amount mode', () {
      final g = grid([
        ['Date', 'Description', 'Amount'],
        ['01/04/2025', 'Grocery', '-450.00'],
        ['02/04/2025', 'Refund', '120.00 CR'],
      ]);
      final rows = buildImportRows(g, suggestMapping(g.header), DateOrder.dmy);
      expect(rows[0].amount, -450.00);
      expect(rows[1].amount, 120.00);
    });

    test('merges wrapped description continuation lines', () {
      final g = grid([
        ['Date', 'Narration', 'Withdrawal', 'Deposit'],
        ['01/04/2025', 'UPI-509912345678-GROCERY', '450.00', ''],
        ['', 'MART PVT LTD', '', ''],
        ['02/04/2025', 'ATM WDL', '2,000.00', ''],
      ]);
      final rows = buildImportRows(g, suggestMapping(g.header), DateOrder.dmy);
      expect(rows.length, 2);
      expect(rows[0].description, 'UPI-509912345678-GROCERY MART PVT LTD');
    });

    test('rows with a date but no amount are kept as unparseable', () {
      final g = grid([
        ['Date', 'Description', 'Amount'],
        ['01/04/2025', 'Opening balance', ''],
        ['02/04/2025', 'Coffee', '-90'],
      ]);
      final rows = buildImportRows(g, suggestMapping(g.header), DateOrder.dmy);
      expect(rows.length, 2);
      expect(rows[0].parseable, false);
      expect(rows[1].parseable, true);
    });
  });

  group('importFingerprint', () {
    test('normalizes and caps the reference text', () {
      final a = importFingerprint(
          accountId: 'acc1',
          date: DateTime(2025, 4, 1),
          amount: -450,
          refOrDesc: 'UPI/509 Grocery-Mart!');
      final b = importFingerprint(
          accountId: 'acc1',
          date: DateTime(2025, 4, 1),
          amount: -450.004,
          refOrDesc: 'upi 509 GROCERY mart');
      expect(a, b);
      expect(a, 'acc1|2025-04-01|-450.00|upi509grocerymart');
    });

    test('differs by account, date and amount', () {
      final base = importFingerprint(
          accountId: 'a', date: DateTime(2025, 1, 1), amount: 10, refOrDesc: 'x');
      expect(
          importFingerprint(
              accountId: 'b', date: DateTime(2025, 1, 1), amount: 10, refOrDesc: 'x'),
          isNot(base));
      expect(
          importFingerprint(
              accountId: 'a', date: DateTime(2025, 1, 2), amount: 10, refOrDesc: 'x'),
          isNot(base));
      expect(
          importFingerprint(
              accountId: 'a', date: DateTime(2025, 1, 1), amount: -10, refOrDesc: 'x'),
          isNot(base));
    });
  });

  group('parseStatement end-to-end', () {
    test('CSV with preamble → grid with detected header', () {
      final csvText = 'My Bank\nAccount: 1234\n\n'
          'Date,Narration,Debit,Credit\n'
          '01/04/2025,Grocery,450.00,\n'
          '02/04/2025,Salary,,50000.00\n';
      final grid = parseStatement(
          Uint8List.fromList(utf8.encode(csvText)), 'statement.csv');
      expect(grid.kind, StatementKind.csv);
      expect(grid.header, ['Date', 'Narration', 'Debit', 'Credit']);
      expect(grid.dataRows.length, 2);
    });

    test('HTML table mislabelled as .xls', () {
      const html = '<html><body><table>'
          '<tr><th>Date</th><th>Description</th><th>Amount</th></tr>'
          '<tr><td>01/04/2025</td><td>Grocery &amp; Fruit</td><td>-450.00</td></tr>'
          '</table></body></html>';
      final grid =
          parseStatement(Uint8List.fromList(utf8.encode(html)), 'statement.xls');
      expect(grid.kind, StatementKind.html);
      expect(grid.dataRows.single, ['01/04/2025', 'Grocery & Fruit', '-450.00']);
    });

    test('legacy/encrypted Excel container is rejected with guidance', () {
      final ole2 = Uint8List.fromList(
          [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, ...List.filled(64, 0)]);
      expect(
        () => parseStatement(ole2, 'statement.xls'),
        throwsA(isA<StatementUnsupported>()
            .having((e) => e.message, 'message', contains('CSV or PDF'))),
      );
    });

    test('empty file is rejected', () {
      expect(() => parseStatement(Uint8List(0), 'x.csv'),
          throwsA(isA<StatementUnsupported>()));
    });
  });
}
