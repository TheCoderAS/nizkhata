// Shared branding for on-device PDFs (khata ledger, tax pack): a clean white
// header — app logo, wordmark in brand indigo, subtitle, generated date, and
// a hairline divider — drawn entirely at positive coordinates (a previous navy
// band drawn into the top margin clipped in most viewers).

import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Rect;

import 'package:syncfusion_flutter_pdf/pdf.dart';

const pdfBrandIndigo = Color(0xFF4F46E5);

PdfColor pdfColorOf(Color c) =>
    PdfColor((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());

/// Syncfusion's standard PDF fonts cover Latin-1 only; any other code unit
/// throws at layout time. Map common typography to ASCII and blank the rest so
/// arbitrary names and narrations can never crash PDF generation.
String pdfSafe(String s) {
  const map = {
    '—': '-', '–': '-', '−': '-', '‘': "'", '’': "'",
    '“': '"', '”': '"', '…': '...', '₹': 'Rs ', ' ': ' ',
    '•': '-', '·': '.',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    if (map.containsKey(ch)) {
      b.write(map[ch]);
    } else if (r <= 0xFF) {
      b.write(ch);
    } else {
      b.write('?');
    }
  }
  return b.toString();
}

/// Draw the header at the top of [g]; returns the y where content may begin.
double drawPdfBrandHeader(
  PdfGraphics g, {
  required double width,
  required String subtitle,
  required String generatedOn,
  Uint8List? logoPng,
}) {
  const logoSize = 40.0;
  var textX = 0.0;
  if (logoPng != null) {
    try {
      g.drawImage(PdfBitmap(logoPng), Rect.fromLTWH(0, 0, logoSize, logoSize));
      textX = logoSize + 12;
    } catch (_) {
      // A bad asset never breaks the document — fall back to text-only.
    }
  }
  g.drawString('NizKhata',
      PdfStandardFont(PdfFontFamily.helvetica, 20, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(pdfColorOf(pdfBrandIndigo)),
      bounds: Rect.fromLTWH(textX, 0, width - textX, 24));
  g.drawString(pdfSafe(subtitle), PdfStandardFont(PdfFontFamily.helvetica, 10),
      brush: PdfSolidBrush(PdfColor(90, 98, 116)),
      bounds: Rect.fromLTWH(textX, 25, width - textX, 14));
  g.drawString(generatedOn, PdfStandardFont(PdfFontFamily.helvetica, 8),
      brush: PdfSolidBrush(PdfColor(140, 147, 163)),
      bounds: Rect.fromLTWH(textX, 40, width - textX, 12));
  // Hairline divider under the header block.
  g.drawLine(
      PdfPen(PdfColor(225, 228, 235), width: 1), const Offset(0, 58), Offset(width, 58));
  return 70;
}

/// Statement-grade table styling: filled bold header row, hairline borders,
/// zebra striping, and right-aligned money columns — the details that make a
/// generated document read like a real bank statement.
void styleStatementGrid(
  PdfGrid grid, {
  required PdfFont body,
  required PdfFont bold,
  Set<int> rightCols = const {},
}) {
  final border = PdfPen(PdfColor(223, 226, 235), width: 0.5);
  PdfBorders borders() => PdfBorders(left: border, top: border, right: border, bottom: border);
  final rightFmt = PdfStringFormat(alignment: PdfTextAlignment.right);
  grid.style = PdfGridStyle(
      font: body, cellPadding: PdfPaddings(left: 6, right: 6, top: 4, bottom: 4));
  if (grid.headers.count > 0) {
    final h = grid.headers[0];
    for (var i = 0; i < h.cells.count; i++) {
      h.cells[i].style = PdfGridCellStyle(
        backgroundBrush: PdfSolidBrush(PdfColor(232, 234, 246)),
        font: bold,
        borders: borders(),
      );
      if (rightCols.contains(i)) h.cells[i].stringFormat = rightFmt;
    }
  }
  for (var r = 0; r < grid.rows.count; r++) {
    final row = grid.rows[r];
    for (var i = 0; i < row.cells.count; i++) {
      row.cells[i].style = PdfGridCellStyle(
        backgroundBrush: r.isOdd ? PdfSolidBrush(PdfColor(246, 247, 250)) : null,
        borders: borders(),
      );
      if (rightCols.contains(i)) row.cells[i].stringFormat = rightFmt;
    }
  }
}

/// Emphasize one grid row (e.g. a totals row): bold on a light indigo fill.
/// Preserves each cell's alignment (set by [styleStatementGrid] beforehand).
void emphasizeGridRow(PdfGridRow row, PdfFont bold) {
  for (var i = 0; i < row.cells.count; i++) {
    final existingFmt = row.cells[i].stringFormat;
    row.cells[i].style = PdfGridCellStyle(
      font: bold,
      backgroundBrush: PdfSolidBrush(PdfColor(232, 234, 246)),
    );
    row.cells[i].stringFormat = existingFmt;
  }
}

/// Footer on every page: [leftText] plus right-aligned "Page N of M".
void drawPdfPageFooters(PdfDocument doc, String leftText) {
  final small = PdfStandardFont(PdfFontFamily.helvetica, 7.5);
  final gray = PdfSolidBrush(PdfColor(130, 137, 155));
  final n = doc.pages.count;
  for (var i = 0; i < n; i++) {
    final p = doc.pages[i];
    final size = p.getClientSize();
    p.graphics.drawString(pdfSafe(leftText), small,
        brush: gray, bounds: Rect.fromLTWH(0, size.height - 11, size.width - 76, 11));
    p.graphics.drawString('Page ${i + 1} of $n', small,
        brush: gray,
        bounds: Rect.fromLTWH(size.width - 76, size.height - 11, 76, 11),
        format: PdfStringFormat(alignment: PdfTextAlignment.right));
  }
}
