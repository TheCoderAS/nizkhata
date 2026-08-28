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

String _money(double v, String currency) => NumberFormat.currency(
        locale: 'en_IN', symbol: currency == 'INR' ? 'Rs ' : '$currency ', decimalDigits: 2)
    .format(v);

String _pdfSafe(String s) => pdfSafe(s);

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

  final h2 = PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);
  final body = PdfStandardFont(PdfFontFamily.helvetica, 9);
  final small = PdfStandardFont(PdfFontFamily.helvetica, 8);
  final dateFmt = DateFormat('dd MMM yyyy');

  var y = drawPdfBrandHeader(
    g,
    width: w,
    subtitle: 'Tax pack . FY $fy . $workspaceName',
    generatedOn: 'Generated ${dateFmt.format(DateTime.now())}',
    logoPng: logoPng,
  );
  g.drawString(
      _pdfSafe('Total taxable: ${_money(totalTaxable, currency)}    '
          'Total TDS: ${_money(totalTds, currency)}'),
      h2,
      bounds: Rect.fromLTWH(0, y, w, 18));
  y += 30;

  var currentPage = page;
  PdfGridStyle style() =>
      PdfGridStyle(font: body, cellPadding: PdfPaddings(left: 6, right: 6, top: 3, bottom: 3));

  PdfPage section(String title, PdfGrid grid, PdfPage onPage, double atY) {
    onPage.graphics.drawString(title, h2, bounds: Rect.fromLTWH(0, atY, w, 16));
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
      r.cells[0].value = _pdfSafe(e.label);
      r.cells[1].value = _money(e.taxable, currency);
      r.cells[2].value = _money(e.tds, currency);
      r.cells[3].value = '${e.lines}';
    }
    grid.style = style();
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
      r.cells[0].value = _pdfSafe(e.contactName);
      r.cells[1].value = _money(e.taxable, currency);
      r.cells[2].value = _money(e.tds, currency);
    }
    grid.style = style();
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
      r.cells[1].value = _pdfSafe(e.description);
      r.cells[2].value = _pdfSafe(e.headLabel);
      r.cells[3].value = _money(e.taxable, currency);
      r.cells[4].value = _money(e.tds, currency);
    }
    grid.style = style();
    currentPage = section('Taxable-line register (${register.length})', grid, currentPage, y);
  }

  // Footer + disclaimer on every page.
  for (var i = 0; i < doc.pages.count; i++) {
    final p = doc.pages[i];
    final size = p.getClientSize();
    p.graphics.drawString(
        'Prepared from your NizKhata records - please verify with your accountant. '
        'nizkhata.web.app',
        small,
        brush: PdfSolidBrush(PdfColor(120, 128, 148)),
        bounds: Rect.fromLTWH(0, size.height - 12, size.width, 12));
  }

  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}
