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
