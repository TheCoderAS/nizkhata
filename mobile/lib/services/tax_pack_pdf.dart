// The FY tax pack: a financial-year-end PDF a freelancer or small operator
// hands to their CA — taxable totals by head, TDS by contact (for 26AS
// cross-checks), and the full taxable-line register. Generated on-device with
// Syncfusion and passed to the share sheet; no infra involved.

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'pdf_brand.dart';

class TaxHeadSummary {
  final String label;
  final double taxable;
  final double tds;
  final int lines;
  TaxHeadSummary(this.label, this.taxable, this.tds, this.lines);
}

class TaxContactSummary {
  final String contactName;
  final double taxable;
  final double tds;
  TaxContactSummary(this.contactName, this.taxable, this.tds);
}

class TaxRegisterRow {
  final DateTime date;
  final String description;
  final String headLabel;
  final double taxable;
  final double tds;
  TaxRegisterRow(this.date, this.description, this.headLabel, this.taxable, this.tds);
}

Uint8List buildTaxPackPdf({
  required String workspaceName,
  required String fy,
  required String currency,
  required double totalTaxable,
  required double totalTds,
  required List<TaxHeadSummary> heads,
  required List<TaxContactSummary> contacts,
  required List<TaxRegisterRow> register,
  Uint8List? logoPng,
}) {
  final doc = PdfDocument();
  doc.pageSettings.margins.all = 36;
  final page = doc.pages.add();
  final g = page.graphics;
  final w = page.getClientSize().width;

  final fonts = PdfFonts();
  final h2 = fonts.bold(12);
  final body = fonts.regular(9);
  final bodyBold = fonts.bold(9);
  final small = fonts.regular(8);
  final dateFmt = DateFormat('dd MMM yyyy');
  final fmt = fonts.format();
  // The workspace currency's own symbol, decimals and grouping.
  String money(double v) => fonts.money(v, currency);
  String safe(String s) => fonts.text(s);

  var y = drawPdfBrandHeader(
    g,
    fonts: fonts,
    width: w,
    subtitle: 'Tax pack for FY $fy ($workspaceName)',
    generatedOn: 'Generated ${dateFmt.format(DateTime.now())}',
    logoPng: logoPng,
  );
  // Text bounds have no height (0 = as tall as the text needs): Syncfusion
  // silently drops a line taller than its bounds, and Noto's lines are taller
  // than Helvetica's were.
  g.drawString(safe('Total taxable: ${money(totalTaxable)}    Total TDS: ${money(totalTds)}'), h2,
      bounds: Rect.fromLTWH(0, y, w, 0), format: fmt);
  y += 30;

  var currentPage = page;

  PdfPage section(String title, PdfGrid grid, PdfPage onPage, double atY) {
    onPage.graphics.drawString(title, h2, bounds: Rect.fromLTWH(0, atY, w, 0), format: fmt);
    final res = grid.draw(page: onPage, bounds: Rect.fromLTWH(0, atY + 20, w, 0));
    if (res != null) {
      y = res.bounds.bottom + 20;
      return res.page;
    }
    y = atY + 40;
    return onPage;
  }

  // 1. By head.
  if (heads.isNotEmpty) {
    final grid = PdfGrid()..columns.add(count: 4);
    grid.headers.add(1);
    final h = grid.headers[0];
    h.cells[0].value = 'Head';
    h.cells[1].value = 'Taxable';
    h.cells[2].value = 'TDS';
    h.cells[3].value = 'Lines';
    for (final e in heads) {
      final r = grid.rows.add();
      r.cells[0].value = safe(e.label);
      r.cells[1].value = money(e.taxable);
      r.cells[2].value = money(e.tds);
      r.cells[3].value = '${e.lines}';
    }
    final totals = grid.rows.add();
    totals.cells[0].value = 'Total';
    totals.cells[1].value = money(totalTaxable);
    totals.cells[2].value = money(totalTds);
    totals.cells[3].value = '';
    styleStatementGrid(grid, fonts: fonts, body: body, bold: bodyBold, rightCols: {1, 2, 3});
    emphasizeGridRow(totals, bodyBold);
    currentPage = section('Taxable by head', grid, currentPage, y);
  }

  // 2. TDS by contact (26AS cross-check).
  if (contacts.isNotEmpty) {
    final grid = PdfGrid()..columns.add(count: 3);
    grid.headers.add(1);
    final h = grid.headers[0];
    h.cells[0].value = 'Contact';
    h.cells[1].value = 'Taxable';
    h.cells[2].value = 'TDS';
    for (final e in contacts) {
      final r = grid.rows.add();
      r.cells[0].value = safe(e.contactName);
      r.cells[1].value = money(e.taxable);
      r.cells[2].value = money(e.tds);
    }
    styleStatementGrid(grid, fonts: fonts, body: body, bold: bodyBold, rightCols: {1, 2});
    currentPage = section('By contact (cross-check against Form 26AS)', grid, currentPage, y);
  }

  // 3. Full register.
  if (register.isNotEmpty) {
    final grid = PdfGrid()..columns.add(count: 5);
    grid.headers.add(1);
    final h = grid.headers[0];
    h.cells[0].value = 'Date';
    h.cells[1].value = 'Description';
    h.cells[2].value = 'Head';
    h.cells[3].value = 'Taxable';
    h.cells[4].value = 'TDS';
    grid.columns[0].width = 66;
    grid.columns[3].width = 80;
    grid.columns[4].width = 70;
    for (final e in register) {
      final r = grid.rows.add();
      r.cells[0].value = dateFmt.format(e.date);
      r.cells[1].value = safe(e.description);
      r.cells[2].value = safe(e.headLabel);
      r.cells[3].value = money(e.taxable);
      r.cells[4].value = money(e.tds);
    }
    styleStatementGrid(grid, fonts: fonts, body: body, bold: bodyBold, rightCols: {3, 4});
    currentPage = section('Taxable-line register (${register.length})', grid, currentPage, y);
  }

  // Closing note (new page if the last table ended near the bottom).
  if (y > currentPage.getClientSize().height - 40) {
    currentPage = doc.pages.add();
    y = 0;
  }
  currentPage.graphics.drawString(
      'Prepared from your NizKhata records. Please verify figures with your '
      'accountant before filing.',
      small,
      brush: PdfSolidBrush(PdfColor(120, 128, 148)),
      bounds: Rect.fromLTWH(0, y + 6, w, 0),
      format: fmt);

  drawPdfPageFooters(
      doc, fonts, 'Computer-generated statement, no signature required | https://nizkhata.web.app');

  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}
