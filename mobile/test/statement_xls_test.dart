import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/services/statement_parser.dart';
import 'package:nizkhata/services/xls_decoder.dart';

// Fixtures generated with python-xlwt (real BIFF8 workbooks in OLE2
// containers, incl. SST shared strings, RK/NUMBER cells and date-formatted
// serial cells).
void main() {
  test('legacy .xls statement parses through the full pipeline', () {
    final bytes = File('test/fixtures/statement_biff8.xls').readAsBytesSync();
    final grid = parseStatement(bytes, 'statement.xls');
    expect(grid.kind, StatementKind.excel);
    expect(grid.header, ['Date', 'Narration', 'Debit', 'Credit']);

    final mapping = suggestMapping(grid.header);
    expect(mapping.splitAmounts, true);
    final rows = buildImportRows(grid, mapping, DateOrder.dmy);
    expect(rows.length, 3);
    // Date-formatted serial cell → ISO text → parsed date.
    expect(rows[0].date, DateTime(2025, 4, 1));
    expect(rows[0].description, 'UPI-GROCERY MART');
    expect(rows[0].amount, -450.0);
    // Text date cell.
    expect(rows[1].date, DateTime(2025, 4, 2));
    expect(rows[1].amount, 50000.0);
    // RK-encoded decimal.
    expect(rows[2].amount, -2000.25);
  });

  test('picks the busiest sheet in a multi-sheet .xls', () {
    final bytes = File('test/fixtures/statement_biff8_multi.xls').readAsBytesSync();
    final rows = decodeXls(bytes);
    expect(rows.first, ['Date', 'Description', 'Amount']);
    expect(rows.length, 40); // header + 39 transactions from the Txns sheet
    expect(rows[5][1], contains('longer narration text'));

    final grid = parseStatement(bytes, 's.xls');
    final drafts = buildImportRows(grid, suggestMapping(grid.header), DateOrder.dmy);
    expect(drafts.length, 39);
    expect(drafts.every((d) => d.parseable), true);
    expect(drafts[0].amount, -101.0);
    expect(drafts[1].amount, 102.0);
  });

  test('garbage OLE2 container gives a clear error', () {
    final junk = List<int>.filled(1024, 0);
    junk.setRange(0, 8, [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
    expect(
      () => parseStatement(Uint8List.fromList(junk), 'x.xls'),
      throwsA(isA<StatementUnsupported>()),
    );
  });
}
