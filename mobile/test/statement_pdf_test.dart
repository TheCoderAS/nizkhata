import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:nizkhata/services/statement_parser.dart';

/// End-to-end check of the PDF path: build a real statement-like PDF (grid of
/// header + rows, optionally password-protected), then run it through
/// [parseStatement] and the shared mapping/row pipeline.
Uint8List _makeStatementPdf({String? password}) {
  final doc = PdfDocument();
  if (password != null) doc.security.userPassword = password;
  final page = doc.pages.add();
  page.graphics.drawString(
      'My Bank — Account Statement', PdfStandardFont(PdfFontFamily.helvetica, 14),
      bounds: const Rect.fromLTWH(0, 0, 400, 20));
  final grid = PdfGrid();
  grid.columns.add(count: 4);
  grid.headers.add(1);
  final header = grid.headers[0];
  header.cells[0].value = 'Date';
  header.cells[1].value = 'Narration';
  header.cells[2].value = 'Withdrawal';
  header.cells[3].value = 'Deposit';
  void row(String d, String n, String w, String dep) {
    final r = grid.rows.add();
    r.cells[0].value = d;
    r.cells[1].value = n;
    r.cells[2].value = w;
    r.cells[3].value = dep;
  }

  row('01/04/2025', 'UPI-GROCERY MART', '450.00', '');
  row('02/04/2025', 'SALARY CREDIT', '', '50,000.00');
  row('15/04/2025', 'ATM WDL REF 8812', '2,000.00', '');
  grid.draw(page: page, bounds: const Rect.fromLTWH(0, 40, 500, 0));
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}

void main() {
  test('plain PDF statement parses into the mapped rows', () {
    final grid = parseStatement(_makeStatementPdf(), 'statement.pdf');
    expect(grid.kind, StatementKind.pdf);
    expect(grid.header.map((h) => h.toLowerCase()).toList(),
        ['date', 'narration', 'withdrawal', 'deposit']);

    final mapping = suggestMapping(grid.header);
    expect(mapping.splitAmounts, true);
    final rows = buildImportRows(grid, mapping, DateOrder.dmy);
    expect(rows.length, 3);
    expect(rows[0].date, DateTime(2025, 4, 1));
    expect(rows[0].amount, -450.00);
    expect(rows[0].description, 'UPI-GROCERY MART');
    expect(rows[1].amount, 50000.00);
    expect(rows[2].amount, -2000.00);
  });

  test('encrypted PDF: prompts for password, wrong rejected, right one opens', () {
    final bytes = _makeStatementPdf(password: 's3cret');
    expect(
      () => parseStatement(bytes, 'statement.pdf'),
      throwsA(isA<StatementPasswordRequired>()
          .having((e) => e.wrongPassword, 'wrongPassword', false)),
    );
    expect(
      () => parseStatement(bytes, 'statement.pdf', password: 'nope'),
      throwsA(isA<StatementPasswordRequired>()
          .having((e) => e.wrongPassword, 'wrongPassword', true)),
    );
    final grid = parseStatement(bytes, 'statement.pdf', password: 's3cret');
    expect(grid.dataRows.length, 3);
  });
}
