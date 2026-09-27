// Shared branding for on-device PDFs (khata ledger, tax pack): a clean white
// header — app logo, wordmark in brand indigo, subtitle, generated date, and
// a hairline divider — drawn entirely at positive coordinates (a previous navy
// band drawn into the top margin clipped in most viewers).
//
// It also owns the typeface. The PDFs go to people in any country, so they are
// set in Noto Sans, embedded from assets/fonts/, rather than the built-in
// Helvetica, which only knows Latin-1: no ₹, no €, and no names in any script
// but Latin. The embedded font is Noto Sans (Latin, Devanagari, the currency
// signs) with Noto Sans Arabic merged in, pinned to static Regular and Bold
// instances and cut down to those scripts, about 140 KB a weight. What it can
// and cannot do is spelled out on [pdfSafe].

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Rect;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../core/currency.dart';

const pdfBrandIndigo = Color(0xFF4F46E5);

PdfColor pdfColorOf(Color c) => PdfColor((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());

/// The embedded PDF typeface, loaded once from the app's assets.
///
/// The PDF builders are synchronous, and assets can only be read
/// asynchronously, so a caller should `await PdfTypeface.load()` before
/// building a PDF. One that does not still gets a correct document, set in
/// Helvetica with currency codes in place of the signs Helvetica lacks, and
/// its call starts the load so the next PDF has the real font.
class PdfTypeface {
  PdfTypeface._();

  static const regularAsset = 'assets/fonts/NotoSansPdf-Regular.ttf';
  static const boldAsset = 'assets/fonts/NotoSansPdf-Bold.ttf';

  static Uint8List? _regular;
  static Uint8List? _bold;
  static Future<void>? _loading;

  static bool get isLoaded => _regular != null && _bold != null;

  /// Load the font from [bundle] (the app's own by default). Safe to call
  /// often: it reads the assets once. Never throws; if the assets cannot be
  /// read, PDFs keep using Helvetica.
  static Future<void> load([AssetBundle? bundle]) {
    if (isLoaded) return Future.value();
    return _loading ??= () async {
      try {
        final b = bundle ?? rootBundle;
        final regular = await b.load(regularAsset);
        final bold = await b.load(boldAsset);
        use(regular: regular.buffer.asUint8List(), bold: bold.buffer.asUint8List());
      } catch (_) {
        // Leave the door open for a later attempt.
        _loading = null;
      }
    }();
  }

  /// Use these font bytes directly, for code that has them without an asset
  /// bundle (tests read them from disk).
  static void use({required Uint8List regular, required Uint8List bold}) {
    _regular = regular;
    _bold = bold;
  }

  /// Forget the font, so PDFs fall back to Helvetica. For tests.
  static void unload() {
    _regular = null;
    _bold = null;
    _loading = null;
  }
}

/// The fonts and text rules for one document.
///
/// Taken once per document, so a font that finishes loading halfway through
/// building one cannot leave it in two typefaces.
class PdfFonts {
  final bool embedded = PdfTypeface.isLoaded;
  final _cache = <String, PdfFont>{};

  PdfFonts() {
    if (!embedded) unawaited(PdfTypeface.load());
  }

  PdfFont regular(double size) => _font(size, false);
  PdfFont bold(double size) => _font(size, true);

  PdfFont _font(double size, bool bold) => _cache.putIfAbsent('$size/$bold', () {
        if (embedded) return PdfTrueTypeFont(bold ? PdfTypeface._bold! : PdfTypeface._regular!, size);
        return PdfStandardFont(PdfFontFamily.helvetica, size, style: bold ? PdfFontStyle.bold : null);
      });

  /// How to lay out a piece of text.
  ///
  /// With the embedded font the text direction is always set: Syncfusion
  /// joins Arabic letters and runs the bidirectional algorithm only when it
  /// is, and without that an Arabic name comes out as separate letters in
  /// reverse order. Left-to-right is the paragraph direction, so English
  /// text and figures are laid out exactly as before, and an Arabic name
  /// inside a line still reads right to left.
  PdfStringFormat format({PdfTextAlignment alignment = PdfTextAlignment.left}) => PdfStringFormat(
        alignment: alignment,
        textDirection: embedded ? PdfTextDirection.leftToRight : PdfTextDirection.none,
      );

  /// [s] made drawable in this document's font; see [pdfSafe].
  String text(String s) => pdfSafe(s, embedded: embedded);

  /// An unsigned-or-signed figure in [currency], written the currency's own
  /// way (symbol, decimals, grouping). Helvetica has no ₹, €, ₩ and the like,
  /// so without the embedded font those currencies show their ISO code
  /// instead, which is still unambiguous.
  String money(num v, String currency) {
    final spec = currencySpec(currency);
    final drawable = embedded || spec.symbol.runes.every((r) => r <= 0xFF);
    return moneyFigure(v, currency, symbol: drawable ? spec.symbol : '${spec.code} ');
  }
}

/// [v] in [currency]'s own notation: its symbol, its number of decimal places
/// (none for the yen, three for the Kuwaiti dinar) and its digit grouping
/// (lakhs and crores for the rupee, thousands elsewhere).
///
/// Unlike formatMoney this writes zero as a figure and a negative with a
/// minus sign: the PDFs and messages put their own sign and wording around
/// the amount, and an em dash would be out of place in a message to a person.
String moneyFigure(num v, String currency, {String? symbol}) {
  final spec = currencySpec(currency);
  return NumberFormat.currency(
    locale: spec.numberLocale,
    symbol: symbol ?? spec.symbol,
    decimalDigits: spec.decimals,
  ).format(v);
}

bool _covered(int r) =>
    (r >= 0x20 && r <= 0x7E) ||
    (r >= 0xA0 && r <= 0x24F) ||
    (r >= 0x2B0 && r <= 0x36F) ||
    (r >= 0x600 && r <= 0x6FF) ||
    (r >= 0x900 && r <= 0x97F) ||
    (r >= 0x1CD0 && r <= 0x1CFF) ||
    (r >= 0x1E00 && r <= 0x1EFF) ||
    (r >= 0x2000 && r <= 0x206F) ||
    (r >= 0x20A0 && r <= 0x20CF) ||
    (r >= 0x2100 && r <= 0x214F) ||
    r == 0x2212 ||
    r == 0x25CC ||
    (r >= 0xA8E0 && r <= 0xA8FF) ||
    (r >= 0xFB50 && r <= 0xFBFF) ||
    (r >= 0xFE70 && r <= 0xFEFF);

const _devanagariShortI = 0x093F;
const _devanagariNukta = 0x093C;

bool _devanagariConsonant(int r) => (r >= 0x915 && r <= 0x939) || (r >= 0x958 && r <= 0x95F);

/// Make [s] safe to draw.
///
/// With the embedded font ([embedded]), what renders, checked by rendering
/// and looking, not assumed:
///  * Latin, including accented and Vietnamese letters, and every currency
///    sign the app offers except the baht and the taka (฿ ৳): correct.
///  * Arabic: correct, letters joined and right to left, alone or inside an
///    English line, as long as the text is drawn with [PdfFonts.format].
///  * Devanagari: legible but not typeset properly. Syncfusion does not apply
///    the font's shaping rules, so a conjunct shows its virama (क्ष reads as
///    क्‌ष) and a reph is written out (र्म as र्‌म). The one fix made here is
///    moving the short-i sign (ि) before its consonant, as shaping would, so
///    that simple syllables such as अमित and हिंदी come out right.
///  * Anything else (Chinese, Tamil, Bengali, Thai, Greek, Cyrillic, emoji):
///    each character is drawn as '?'. The font does not carry those scripts,
///    and a character it lacks would otherwise vanish without a trace, which
///    reads worse than a visible gap.
///
/// Without it, Syncfusion's standard fonts cover Latin-1 only and any other
/// character throws at layout time, so common typography is mapped to ASCII
/// and the rest drawn as '?', so arbitrary names and narrations can never
/// crash PDF generation.
String pdfSafe(String s, {bool embedded = false}) {
  if (embedded) {
    final runes = s.runes.toList();
    for (var i = 1; i < runes.length; i++) {
      if (runes[i] != _devanagariShortI) continue;
      var start = i - 1;
      if (runes[start] == _devanagariNukta && start > 0) start--;
      if (!_devanagariConsonant(runes[start])) continue;
      runes
        ..removeAt(i)
        ..insert(start, _devanagariShortI);
    }
    return String.fromCharCodes([for (final r in runes) _covered(r) ? r : 0x3F]);
  }
  const map = {
    '—': '-',
    '–': '-',
    '−': '-',
    '‘': "'",
    '’': "'",
    '“': '"',
    '”': '"',
    '…': '...',
    ' ': ' ',
    '•': '-',
    '·': '.',
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
  required PdfFonts fonts,
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
  // Bounds are given no height (0 = as tall as the text needs): Noto's line
  // is taller than Helvetica's, and Syncfusion silently drops a line that
  // does not fit its bounds.
  g.drawString('NizKhata', fonts.bold(20),
      brush: PdfSolidBrush(pdfColorOf(pdfBrandIndigo)),
      bounds: Rect.fromLTWH(textX, 0, width - textX, 0),
      format: fonts.format());
  g.drawString(fonts.text(subtitle), fonts.regular(10),
      brush: PdfSolidBrush(PdfColor(90, 98, 116)),
      bounds: Rect.fromLTWH(textX, 25, width - textX, 0),
      format: fonts.format());
  g.drawString(fonts.text(generatedOn), fonts.regular(8),
      brush: PdfSolidBrush(PdfColor(140, 147, 163)),
      bounds: Rect.fromLTWH(textX, 40, width - textX, 0),
      format: fonts.format());
  // Hairline divider under the header block.
  g.drawLine(PdfPen(PdfColor(225, 228, 235), width: 1), const Offset(0, 58), Offset(width, 58));
  return 70;
}

/// Statement-grade table styling: filled bold header row, hairline borders,
/// zebra striping, and right-aligned money columns — the details that make a
/// generated document read like a real bank statement.
void styleStatementGrid(
  PdfGrid grid, {
  required PdfFonts fonts,
  required PdfFont body,
  required PdfFont bold,
  Set<int> rightCols = const {},
}) {
  final border = PdfPen(PdfColor(223, 226, 235), width: 0.5);
  PdfBorders borders() => PdfBorders(left: border, top: border, right: border, bottom: border);
  final leftFmt = fonts.format();
  final rightFmt = fonts.format(alignment: PdfTextAlignment.right);
  grid.style = PdfGridStyle(font: body, cellPadding: PdfPaddings(left: 6, right: 6, top: 4, bottom: 4));
  if (grid.headers.count > 0) {
    final h = grid.headers[0];
    for (var i = 0; i < h.cells.count; i++) {
      h.cells[i].style = PdfGridCellStyle(
        backgroundBrush: PdfSolidBrush(PdfColor(232, 234, 246)),
        font: bold,
        borders: borders(),
      );
      h.cells[i].stringFormat = rightCols.contains(i) ? rightFmt : leftFmt;
    }
  }
  for (var r = 0; r < grid.rows.count; r++) {
    final row = grid.rows[r];
    for (var i = 0; i < row.cells.count; i++) {
      row.cells[i].style = PdfGridCellStyle(
        backgroundBrush: r.isOdd ? PdfSolidBrush(PdfColor(246, 247, 250)) : null,
        borders: borders(),
      );
      row.cells[i].stringFormat = rightCols.contains(i) ? rightFmt : leftFmt;
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
void drawPdfPageFooters(PdfDocument doc, PdfFonts fonts, String leftText) {
  final small = fonts.regular(7.5);
  final gray = PdfSolidBrush(PdfColor(130, 137, 155));
  final n = doc.pages.count;
  final lineHeight = small.height;
  for (var i = 0; i < n; i++) {
    final p = doc.pages[i];
    final size = p.getClientSize();
    final top = size.height - lineHeight;
    p.graphics.drawString(fonts.text(leftText), small,
        brush: gray, bounds: Rect.fromLTWH(0, top, size.width - 76, lineHeight), format: fonts.format());
    p.graphics.drawString('Page ${i + 1} of $n', small,
        brush: gray,
        bounds: Rect.fromLTWH(size.width - 76, top, 76, lineHeight),
        format: fonts.format(alignment: PdfTextAlignment.right));
  }
}
