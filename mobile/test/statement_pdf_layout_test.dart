import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:nizkhata/services/statement_parser.dart';

/// Build a statement PDF by drawing *positioned text* (not a PdfGrid), the way
/// real bank statements are laid out: fixed column x-positions, right-aligned
/// amounts, a centred multi-word header, and some transactions whose narration
/// wraps onto a second line with no date. This is the layout the header-driven
/// parser mishandled.
Uint8List _bankStatementPdf() {
  final doc = PdfDocument();
  final page = doc.pages.add();
  final g = page.graphics;
  final font = PdfStandardFont(PdfFontFamily.helvetica, 9);
  final bold = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);

  void draw(String s, double x, double y, {PdfFont? f}) {
    g.drawString(s, f ?? font, bounds: Rect.fromLTWH(x, y, 400, 14));
  }

  // Right-align a value so its right edge sits at [rightX].
  void drawRight(String s, double rightX, double y, {PdfFont? f}) {
    final used = f ?? font;
    final w = used.measureString(s).width;
    g.drawString(s, used, bounds: Rect.fromLTWH(rightX - w, y, w + 2, 14));
  }

  // Preamble (account metadata) — must be ignored.
  draw('HDFC BANK LIMITED', 40, 20, f: bold);
  draw('Statement of account 5011 2233 4455', 40, 36);

  // Column x-anchors.
  const xDate = 40.0, xNarr = 120.0, xRefRight = 340.0, xDebitRight = 430.0, xCreditRight = 520.0;

  // Header (centred-ish multi-word labels).
  const yh = 70.0;
  draw('Date', xDate, yh, f: bold);
  draw('Narration', xNarr, yh, f: bold);
  drawRight('Chq/Ref No', xRefRight, yh, f: bold);
  drawRight('Withdrawal', xDebitRight, yh, f: bold);
  drawRight('Deposit', xCreditRight, yh, f: bold);

  // Rows. Some wrap onto a continuation line (narration only, no date/amount).
  var y = 92.0;
  void row(String date, String narr, String ref, String debit, String credit) {
    if (date.isNotEmpty) draw(date, xDate, y);
    draw(narr, xNarr, y);
    if (ref.isNotEmpty) drawRight(ref, xRefRight, y);
    if (debit.isNotEmpty) drawRight(debit, xDebitRight, y);
    if (credit.isNotEmpty) drawRight(credit, xCreditRight, y);
    y += 16;
  }

  row('01/04/2025', 'UPI-GROCERYMART-PAY', '509912', '1,450.00', '');
  row('', 'UPI REF 4457781', '', '', ''); // wrapped narration, no date
  row('02/04/2025', 'NEFT SALARY CREDIT', 'N0294', '', '52,340.00');
  row('05/04/2025', 'ATM WITHDRAWAL', 'S8812', '2,000.00', '');
  row('12/04/2025', 'IMPS RENT', 'IMPS771', '18,000.00', '');
  row('28/04/2025', 'INTEREST CREDIT', '', '', '213.55');

  // Footer summary — must not become a transaction.
  y += 8;
  draw('Closing Balance', xNarr, y);
  drawRight('31,103.55', xCreditRight, y);

  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}

void main() {
  test('positioned-text statement: columns, right-aligned amounts, wraps, footer', () {
    final grid = parseStatement(_bankStatementPdf(), 'statement.pdf');
    expect(grid.kind, StatementKind.pdf);

    final mapping = suggestMapping(grid.header);
    expect(mapping.date, isNotNull);
    expect(mapping.splitAmounts, true, reason: 'should detect withdrawal/deposit columns');

    final rows = buildImportRows(grid, mapping, DateOrder.dmy);
    // 5 dated transactions (the wrapped line merges into the first; the footer
    // is dropped).
    expect(rows.length, 5);
    expect(rows.every((r) => r.parseable), true,
        reason: 'every amount should land in the right column');

    expect(rows[0].date, DateTime(2025, 4, 1));
    expect(rows[0].amount, -1450.00);
    expect(rows[0].description, contains('GROCERYMART'));
    expect(rows[0].description, contains('4457781')); // wrapped line merged

    expect(rows[1].amount, 52340.00); // deposit → positive
    expect(rows[2].amount, -2000.00);
    expect(rows[3].amount, -18000.00);
    expect(rows[4].amount, 213.55);

    // Footer never became a row.
    expect(rows.any((r) => r.description.toLowerCase().contains('closing')), false);
  });
}
