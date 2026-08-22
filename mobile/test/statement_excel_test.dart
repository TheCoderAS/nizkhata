import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/services/statement_parser.dart';

void main() {
  test('xlsx statement parses through the full pipeline', () {
    final workbook = Excel.createExcel();
    final sheet = workbook[workbook.getDefaultSheet()!];
    sheet.appendRow([TextCellValue('My Bank statement')]);
    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Description'),
      TextCellValue('Debit'),
      TextCellValue('Credit'),
    ]);
    sheet.appendRow([
      TextCellValue('01/04/2025'),
      TextCellValue('UPI-GROCERY'),
      DoubleCellValue(450.0),
      TextCellValue(''),
    ]);
    sheet.appendRow([
      DateCellValue(year: 2025, month: 4, day: 2),
      TextCellValue('SALARY'),
      TextCellValue(''),
      IntCellValue(50000),
    ]);
    final bytes = Uint8List.fromList(workbook.encode()!);

    final grid = parseStatement(bytes, 'statement.xlsx');
    expect(grid.kind, StatementKind.excel);
    expect(grid.header, ['Date', 'Description', 'Debit', 'Credit']);

    final mapping = suggestMapping(grid.header);
    final rows = buildImportRows(grid, mapping, DateOrder.dmy);
    expect(rows.length, 2);
    expect(rows[0].amount, -450.0);
    expect(rows[0].date, DateTime(2025, 4, 1));
    // Native Excel date cell comes through as ISO text and still parses.
    expect(rows[1].date, DateTime(2025, 4, 2));
    expect(rows[1].amount, 50000.0);
  });
}
