import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/services/statement_parser.dart';
import 'package:nizkhata/services/xlsx_reader.dart';

// Fixtures are openpyxl-authored .xlsx files — exactly the kind the old
// `excel` package threw on. These exercise the in-house reader instead.
void main() {
  test('plain .xlsx (text dates) parses through the full pipeline', () {
    final bytes = File('test/fixtures/statement_plain.xlsx').readAsBytesSync();
    final grid = parseStatement(bytes, 'statement.xlsx');
    expect(grid.kind, StatementKind.excel);
    expect(grid.header, ['Date', 'Narration', 'Debit', 'Credit']);

    final rows = buildImportRows(grid, suggestMapping(grid.header), DateOrder.dmy);
    expect(rows.length, 3);
    expect(rows[0].amount, -450.0);
    expect(rows[0].date, DateTime(2025, 4, 1));
    expect(rows[1].amount, 50000.0);
    expect(rows[2].amount, -2000.25);
  });

  test('date-styled cells across sheets: busiest sheet + serial→date', () {
    final bytes = File('test/fixtures/statement_dates.xlsx').readAsBytesSync();
    // The reader should skip the "Summary" sheet and pick "Transactions".
    final raw = readXlsx(bytes);
    expect(raw.first, ['Txn Date', 'Description', 'Debit', 'Credit']);
    // Date-typed cells (two different date number formats) → ISO text.
    expect(raw[1][0], '2025-04-01');
    expect(raw[2][0], '2025-04-02');

    final grid = parseStatement(bytes, 'statement.xlsx');
    final rows = buildImportRows(grid, suggestMapping(grid.header), DateOrder.dmy);
    expect(rows.length, 3);
    expect(rows[0].date, DateTime(2025, 4, 1));
    expect(rows[0].amount, -450.0);
    expect(rows[1].date, DateTime(2025, 4, 2));
    expect(rows[1].amount, 50000.0);
    expect(rows[2].amount, -2000.25);
  });

  test('non-xlsx bytes raise a clear error', () {
    expect(() => readXlsx(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<XlsxError>()));
  });
}
