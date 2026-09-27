// Statement parsing — every supported format (CSV/TSV, XLSX, PDF, and the
// HTML-table files many banks mislabel ".xls") is reduced to the same simple
// thing: a grid of strings plus a detected header row. From there one shared
// pipeline handles column mapping, date/amount normalization and row building.
//
// Everything runs on-device. Passwords are used only to open the document in
// memory and are never stored or transmitted.

import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../core/currency.dart';
import 'office_crypto.dart';
import 'xls_decoder.dart';
import 'xlsx_reader.dart';

/// What the picked file turned out to be (by content sniffing, not extension).
enum StatementKind { csv, excel, pdf, html }

/// The PDF is encrypted: no password was given, or the given one is wrong.
class StatementPasswordRequired implements Exception {
  final bool wrongPassword;
  StatementPasswordRequired({required this.wrongPassword});
  @override
  String toString() => wrongPassword ? 'Incorrect password.' : 'This PDF is password-protected.';
}

/// The file can't be parsed on-device; [message] says why and what to do.
class StatementUnsupported implements Exception {
  final String message;
  StatementUnsupported(this.message);
  @override
  String toString() => message;
}

/// Uniform result of the format-specific stage: rows of trimmed cell strings
/// with the most header-like row identified.
class StatementGrid {
  final StatementKind kind;
  final List<List<String>> rows;
  final int headerRow;
  StatementGrid({required this.kind, required this.rows, required this.headerRow});

  List<String> get header => rows.isEmpty ? const [] : rows[headerRow];
  List<List<String>> get dataRows => headerRow + 1 >= rows.length ? const [] : rows.sublist(headerRow + 1);
}

// ---- entry point -----------------------------------------------------------

/// Sniff [bytes] and parse into a [StatementGrid]. Throws
/// [StatementPasswordRequired] for encrypted PDFs and [StatementUnsupported]
/// for formats that can't be opened on-device.
StatementGrid parseStatement(Uint8List bytes, String filename, {String? password}) {
  if (bytes.isEmpty) throw StatementUnsupported('The file is empty.');

  if (_startsWith(bytes, const [0x25, 0x50, 0x44, 0x46])) {
    // %PDF
    return _pdfGrid(bytes, password);
  }
  if (_startsWith(bytes, const [0x50, 0x4B, 0x03, 0x04])) {
    // PK zip → .xlsx
    return _excelGrid(bytes);
  }
  if (_startsWith(bytes, const [0xD0, 0xCF, 0x11, 0xE0])) {
    // OLE2 compound file. Two cases:
    //  (a) a password-encrypted OOXML document (modern .xlsx wrapped in
    //      EncryptionInfo/EncryptedPackage) — decrypt it here, then parse the
    //      inner .xlsx zip;
    //  (b) a legacy binary .xls — read directly with our BIFF decoder.
    if (isEncryptedOfficeContainer(bytes)) {
      if (password == null || password.isEmpty) {
        throw StatementPasswordRequired(wrongPassword: false);
      }
      Uint8List decrypted;
      try {
        decrypted = decryptOfficeDocument(bytes, password);
      } on WrongOfficePassword {
        throw StatementPasswordRequired(wrongPassword: true);
      } on UnsupportedOfficeEncryption catch (e) {
        throw StatementUnsupported("This protected Excel file uses an encryption we can't open "
            'on-device (${e.message}). Please export the statement as CSV or '
            'PDF and try again.');
      }
      return _excelGrid(decrypted);
    }
    try {
      final rows = decodeXls(bytes);
      if (rows.isEmpty) throw StatementUnsupported('The Excel file has no data.');
      return StatementGrid(kind: StatementKind.excel, rows: rows, headerRow: detectHeaderRow(rows));
    } on XlsPasswordProtected {
      throw StatementUnsupported('This is a password-protected legacy .xls file, whose old encryption '
          "can't be opened on-device. Re-save it as .xlsx (Excel → Save As), "
          'or export the statement as CSV or PDF, and try again.');
    } on XlsUnreadable catch (e) {
      throw StatementUnsupported("This legacy Excel file couldn't be read (${e.message}) — "
          'export the statement as CSV, XLSX or PDF instead.');
    }
  }

  // Text: HTML table disguised as .xls (common bank export) or CSV/TSV.
  final text = _decodeText(bytes);
  final head = text.length > 4096 ? text.substring(0, 4096).toLowerCase() : text.toLowerCase();
  if (head.contains('<html') || head.contains('<table')) {
    final rows = _parseHtmlTables(text);
    if (rows.isEmpty) {
      throw StatementUnsupported('No table was found in this file.');
    }
    return StatementGrid(kind: StatementKind.html, rows: rows, headerRow: detectHeaderRow(rows));
  }
  final rows = parseDelimitedText(text);
  if (rows.isEmpty) {
    throw StatementUnsupported('No rows could be read from this file.');
  }
  return StatementGrid(kind: StatementKind.csv, rows: rows, headerRow: detectHeaderRow(rows));
}

bool _startsWith(Uint8List bytes, List<int> magic) {
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) return false;
  }
  return true;
}

String _decodeText(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

// ---- CSV / TSV -------------------------------------------------------------

/// Parse delimited text into trimmed cells, auto-detecting the delimiter
/// (comma / semicolon / tab / pipe) and dropping fully-empty rows.
List<List<String>> parseDelimitedText(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final delimiter = _detectDelimiter(normalized);
  final parsed = CsvToListConverter(
    fieldDelimiter: delimiter,
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(normalized);
  final rows = <List<String>>[];
  for (final raw in parsed) {
    final cells = [for (final c in raw) c.toString().trim()];
    if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
  }
  _padRows(rows);
  return rows;
}

/// The delimiter that splits the most lines into the same number of fields.
///
/// Counting raw occurrences is not enough: a European export separates
/// fields with ';' precisely because ',' is its decimal mark, so a line like
/// `01.02.2026;Rewe, Berlin;-12,50` holds as many commas as semicolons. What
/// tells the real delimiter apart is consistency: it appears the same number
/// of times on every line, header included, while a decimal comma comes and
/// goes with the data. Ties on consistency go to the busier delimiter, and
/// then to the order of the list, so a plain comma file reads as it always has.
String _detectDelimiter(String text) {
  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).take(20).toList();
  var best = ',';
  var bestLines = -1;
  var bestFields = -1;
  for (final d in const [',', ';', '\t', '|']) {
    // How many lines have each count of (unquoted) delimiters.
    final tally = <int, int>{};
    for (final l in lines) {
      final n = _countUnquoted(l, d);
      if (n > 0) tally[n] = (tally[n] ?? 0) + 1;
    }
    var agreeing = 0, fields = 0;
    tally.forEach((n, count) {
      if (count > agreeing || (count == agreeing && n > fields)) {
        agreeing = count;
        fields = n;
      }
    });
    if (agreeing > bestLines || (agreeing == bestLines && fields > bestFields)) {
      bestLines = agreeing;
      bestFields = fields;
      best = d;
    }
  }
  return best;
}

/// Occurrences of [d] in [line] outside double-quoted fields, so a quoted
/// description such as "UPI, Grocery Mart" does not vote for the comma.
int _countUnquoted(String line, String d) {
  var n = 0;
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      quoted = !quoted;
    } else if (!quoted && c == d) {
      n++;
    }
  }
  return n;
}

void _padRows(List<List<String>> rows) {
  var width = 0;
  for (final r in rows) {
    if (r.length > width) width = r.length;
  }
  for (final r in rows) {
    while (r.length < width) {
      r.add('');
    }
  }
}

// ---- Excel (.xlsx) ---------------------------------------------------------

StatementGrid _excelGrid(Uint8List bytes) {
  final List<List<String>> rows;
  try {
    rows = readXlsx(bytes);
  } on XlsxError catch (e) {
    throw StatementUnsupported("This Excel file couldn't be read (${e.message}). If it's "
        'password-protected, enter its password; otherwise export it as CSV or PDF.');
  }
  return StatementGrid(kind: StatementKind.excel, rows: rows, headerRow: detectHeaderRow(rows));
}

// ---- HTML table (files banks mislabel ".xls") ------------------------------

final _trRe = RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
final _cellRe = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', caseSensitive: false, dotAll: true);
final _tagRe = RegExp(r'<[^>]+>');

List<List<String>> _parseHtmlTables(String html) {
  final rows = <List<String>>[];
  for (final tr in _trRe.allMatches(html)) {
    final cells = <String>[];
    for (final td in _cellRe.allMatches(tr.group(1)!)) {
      cells.add(_htmlText(td.group(1)!));
    }
    if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
  }
  _padRows(rows);
  return rows;
}

String _htmlText(String fragment) {
  var t = fragment.replaceAll(_tagRe, ' ');
  t = t
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ---- PDF -------------------------------------------------------------------

StatementGrid _pdfGrid(Uint8List bytes, String? password) {
  PdfDocument doc;
  try {
    doc = PdfDocument(inputBytes: bytes, password: password);
  } catch (e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('password') || msg.contains('encrypt')) {
      throw StatementPasswordRequired(wrongPassword: password != null && password.isNotEmpty);
    }
    throw StatementUnsupported("This PDF couldn't be opened: $e");
  }
  try {
    final lines = PdfTextExtractor(doc).extractTextLines();
    final rows = _pdfLinesToGrid(lines);
    if (rows == null) {
      throw StatementUnsupported('No transaction table was found in this PDF. If the statement is a '
          'scanned image, export a CSV from your bank instead.');
    }
    return StatementGrid(kind: StatementKind.pdf, rows: rows, headerRow: 0);
  } finally {
    doc.dispose();
  }
}

/// Rebuild the transaction table from positioned PDF text. Column boundaries
/// are derived from the *data* layout — the vertical whitespace gutters that
/// persist across the real transaction rows — rather than from where the
/// header labels happen to sit (bank headers are often centred or wrapped, so
/// header-derived boundaries misplaced right-aligned amounts). The header line
/// is still located, to know where the table starts and to label the columns.
List<List<String>>? _pdfLinesToGrid(List<TextLine> lines) {
  // Locate the most header-like line (≥2 keyword groups matched).
  var headerIdx = -1;
  var headerScoreBest = 1;
  for (var i = 0; i < lines.length; i++) {
    final score = headerScore(_lineWordTexts(lines[i]));
    if (score > headerScoreBest) {
      headerScoreBest = score;
      headerIdx = i;
      if (score >= 4) break;
    }
  }
  if (headerIdx < 0) return null;
  final headerLine = lines[headerIdx];
  final headerNorm = _normText(headerLine.text);

  // Data rows below the header that clearly look like transactions (carry a
  // date, or an amount with a decimal). These define the column geometry.
  final dataLines = <TextLine>[];
  for (var i = headerIdx + 1; i < lines.length; i++) {
    if (_normText(lines[i].text) == headerNorm) continue; // repeated page header
    if (_looksLikeTableRow(lines[i])) dataLines.add(lines[i]);
  }
  if (dataLines.length < 2) return null;

  final boundaries = _columnBoundaries(dataLines) ?? _headerBoundaries(headerLine);
  if (boundaries == null || boundaries.isEmpty) return null;

  int colOf(double centreX) {
    for (var b = 0; b < boundaries.length; b++) {
      if (centreX < boundaries[b]) return b;
    }
    return boundaries.length;
  }

  List<String> assign(TextLine line) {
    final cells = List<String>.filled(boundaries.length + 1, '');
    for (final w in line.wordCollection) {
      final text = w.text.trim();
      if (text.isEmpty) continue;
      final col = colOf(w.bounds.left + w.bounds.width / 2);
      cells[col] = cells[col].isEmpty ? text : '${cells[col]} $text';
    }
    return cells;
  }

  final rows = <List<String>>[assign(headerLine)];
  for (var i = headerIdx + 1; i < lines.length; i++) {
    if (_normText(lines[i].text) == headerNorm) continue;
    final cells = assign(lines[i]);
    if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
  }
  return rows.length > 1 ? rows : null;
}

/// A line that reads like a transaction row: at least two words and either a
/// parseable date or a decimal amount somewhere in it.
bool _looksLikeTableRow(TextLine line) {
  final words = [for (final w in line.wordCollection) w.text.trim()]..removeWhere((w) => w.isEmpty);
  if (words.length < 2) return false;
  var hasDate = false, hasAmount = false;
  for (final w in words) {
    if (!hasDate && parseFlexibleDate(w, DateOrder.dmy) != null) hasDate = true;
    if (!hasAmount) {
      // Either decimal mark: the table has to be found before its columns,
      // and so its decimal mark, are known.
      final a = parseAmountText(w) ?? parseAmountText(w, decimalSeparator: ',');
      if (a != null && (w.contains('.') || w.contains(','))) hasAmount = true;
    }
  }
  return hasDate || hasAmount;
}

/// Column boundaries from a projection profile: x positions where the data
/// rows leave a persistent vertical gutter (ink on both sides, empty in the
/// middle across ≥85% of rows). Returns null if fewer than one gutter is found.
List<double>? _columnBoundaries(List<TextLine> dataLines) {
  var minX = double.infinity, maxX = -double.infinity;
  for (final line in dataLines) {
    for (final w in line.wordCollection) {
      if (w.text.trim().isEmpty) continue;
      if (w.bounds.left < minX) minX = w.bounds.left;
      if (w.bounds.right > maxX) maxX = w.bounds.right;
    }
  }
  if (!minX.isFinite || maxX <= minX) return null;

  final lo = minX.floor();
  final width = (maxX.ceil() - lo) + 1;
  if (width <= 0 || width > 20000) return null;
  // coverage[x] = how many data rows have ink at column x.
  final coverage = List<int>.filled(width, 0);
  for (final line in dataLines) {
    // Mark this row's covered bins once (union of its words).
    final marked = List<bool>.filled(width, false);
    for (final w in line.wordCollection) {
      if (w.text.trim().isEmpty) continue;
      final l = (w.bounds.left.floor() - lo).clamp(0, width - 1);
      final r = (w.bounds.right.ceil() - lo).clamp(0, width - 1);
      for (var x = l; x <= r; x++) {
        marked[x] = true;
      }
    }
    for (var x = 0; x < width; x++) {
      if (marked[x]) coverage[x]++;
    }
  }

  final n = dataLines.length;
  // A bin is "gutter material" if almost no row has ink there. floor() keeps
  // this at 0 for small statements (so a column populated in only one row is
  // still recognised as a column, not swallowed into a margin) while tolerating
  // ~15% description bleed once there are enough rows.
  final emptyThreshold = (n * 0.15).floor();
  const minGutter = 3; // points; ignore tiny inter-word gaps

  final boundaries = <double>[];
  var x = 0;
  var seenInk = false; // only count gutters between real columns, not margins
  while (x < width) {
    if (coverage[x] > emptyThreshold) {
      seenInk = true;
      x++;
      continue;
    }
    // Start of a low-coverage run.
    final start = x;
    while (x < width && coverage[x] <= emptyThreshold) {
      x++;
    }
    final end = x; // exclusive
    final hasInkAfter = x < width;
    if (seenInk && hasInkAfter && (end - start) >= minGutter) {
      boundaries.add(lo + (start + end) / 2.0);
    }
  }
  return boundaries.isEmpty ? null : boundaries;
}

/// Fallback: boundaries from the header line's word clusters (used only when
/// the data-driven profile finds no gutters).
List<double>? _headerBoundaries(TextLine headerLine) {
  final clusters = _clusterWords(headerLine);
  if (clusters.length < 2) return null;
  return [
    for (var i = 0; i + 1 < clusters.length; i++) (clusters[i].right + clusters[i + 1].left) / 2,
  ];
}

List<String> _lineWordTexts(TextLine line) => [for (final w in line.wordCollection) w.text.trim()];

String _normText(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

class _Cluster {
  double left;
  double right;
  String text;
  _Cluster(this.left, this.right, this.text);
}

/// Group a line's words into column-label clusters: a new cluster starts when
/// the gap to the previous word clearly exceeds an intra-label word space.
List<_Cluster> _clusterWords(TextLine line) {
  final words = [...line.wordCollection.where((w) => w.text.trim().isNotEmpty)]
    ..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
  final clusters = <_Cluster>[];
  for (final w in words) {
    final h = w.bounds.height;
    final gapThreshold = h > 0 ? h * 1.2 : 10.0;
    if (clusters.isNotEmpty && w.bounds.left - clusters.last.right <= gapThreshold) {
      clusters.last
        ..right = w.bounds.right
        ..text = '${clusters.last.text} ${w.text.trim()}';
    } else {
      clusters.add(_Cluster(w.bounds.left, w.bounds.right, w.text.trim()));
    }
  }
  return clusters;
}

// ---- header detection ------------------------------------------------------

const _headerGroups = <String, List<String>>{
  'date': ['date'],
  'desc': ['description', 'narration', 'particular', 'details', 'remarks'],
  'debit': ['debit', 'withdrawal', 'paid out'],
  'credit': ['credit', 'deposit', 'paid in'],
  'amount': ['amount'],
  'balance': ['balance'],
  'ref': ['ref', 'cheque', 'chq', 'utr'],
};

/// How many distinct header-keyword groups the cells match.
int headerScore(List<String> cells) {
  final joined = cells.join(' ').toLowerCase();
  var score = 0;
  for (final words in _headerGroups.values) {
    if (words.any(joined.contains)) score++;
  }
  return score;
}

/// The most header-like row among the first 40 (bank files often lead with
/// account metadata before the table). Falls back to row 0.
int detectHeaderRow(List<List<String>> rows) {
  var best = 0;
  var bestScore = 1; // require ≥2 to beat the default
  final limit = rows.length < 40 ? rows.length : 40;
  for (var i = 0; i < limit; i++) {
    final s = headerScore(rows[i]);
    if (s > bestScore) {
      bestScore = s;
      best = i;
    }
  }
  return best;
}

// ---- column mapping --------------------------------------------------------

class ColumnMapping {
  int? date;
  int? description;
  int? amount; // single signed/CR-DR amount column
  int? debit; // separate withdrawal column
  int? credit; // separate deposit column
  // A column saying which way a single amount runs: "Debit"/"Credit", "Dr"/
  // "Cr", "W"/"D". Common on Indian card and bank statements, which print one
  // unsigned Amount column and a direction beside it.
  int? direction;
  int? reference;
  int? balance; // running balance — used for reconciliation, never imported
  // The character that marks the decimals in this file's amounts: '.' as in
  // 1,234.56 (India, the US, Britain) or ',' as in 1.234,56 (most of Europe,
  // Latin America). It is a property of the file, not of the workspace, so it
  // is read from the amounts themselves (see [detectDecimalSeparator]). Null
  // means "not chosen yet": [buildImportRows] then detects it, so no caller
  // can get European amounts wrong by forgetting to ask.
  String? decimalSeparator;
  ColumnMapping({
    this.date,
    this.description,
    this.amount,
    this.debit,
    this.credit,
    this.direction,
    this.reference,
    this.balance,
    this.decimalSeparator,
  });

  /// Two-column (debit/credit) mode vs single-amount mode.
  bool get splitAmounts => debit != null || credit != null;
  bool get complete => date != null && (amount != null || splitAmounts);
}

/// Which way a row runs, read from a direction cell.
///
/// Returns null when the cell says nothing recognisable, so an unreadable
/// direction leaves the amount's own sign to speak rather than silently
/// turning every row into money out.
bool? isMoneyOutCell(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return null;
  // Longest-first: "credit" must be tested before "cr", and note that "dr"
  // is a prefix of nothing else here.
  if (t.startsWith('debit') || t.startsWith('withdraw') || t == 'dr' || t == 'd' || t == 'w') {
    return true;
  }
  if (t.startsWith('credit') || t.startsWith('deposit') || t == 'cr' || t == 'c') return false;
  return null;
}

/// Best-guess mapping from header labels. The user can override on-screen.
///
/// Headers say nothing about the decimal mark; call
/// [detectMappingDecimalSeparator] once the amount columns are known.
ColumnMapping suggestMapping(List<String> header) {
  final m = ColumnMapping();
  final cells = [for (final h in header) h.toLowerCase()];

  bool freeFor(int i) =>
      i != m.date &&
      i != m.description &&
      i != m.debit &&
      i != m.credit &&
      i != m.direction &&
      i != m.amount &&
      i != m.reference &&
      i != m.balance;

  // Balance first, so amount/debit/credit guesses never claim the balance
  // column (their keyword checks also exclude 'balance', belt and braces).
  for (var i = 0; i < cells.length; i++) {
    final h = cells[i];
    if (h.isEmpty) continue;
    if (m.balance == null && h.contains('balance')) {
      m.balance = i;
      break;
    }
  }

  for (var i = 0; i < cells.length; i++) {
    final h = cells[i];
    if (h.isEmpty) continue;
    if (m.date == null && h.contains('date') && !h.contains('value')) m.date = i;
  }
  // Fall back to a value-date column if no other date column exists.
  if (m.date == null) {
    for (var i = 0; i < cells.length; i++) {
      if (cells[i].contains('date')) {
        m.date = i;
        break;
      }
    }
  }
  for (var i = 0; i < cells.length; i++) {
    final h = cells[i];
    if (h.isEmpty || !freeFor(i)) continue;
    if (m.description == null &&
        !h.contains('date') &&
        const ['description', 'narration', 'particular', 'details', 'remarks'].any(h.contains)) {
      m.description = i;
    }
  }
  // A header naming BOTH directions ("Debit/Credit", "Dr/Cr", "Cr/Dr") is a
  // direction flag, not an amount. Claiming it as the debit column was how a
  // perfectly ordinary card statement parsed to zero rows: the amount column
  // was never looked for, and every "Debit" cell held no number.
  for (var i = 0; i < cells.length; i++) {
    final h = cells[i];
    if (h.isEmpty || !freeFor(i)) continue;
    final namesBoth = (h.contains('debit') || h.contains('dr')) && (h.contains('credit') || h.contains('cr'));
    if (m.direction == null && (namesBoth || h.contains('type') || h.contains('dr/cr'))) {
      m.direction = i;
      break;
    }
  }
  for (var i = 0; i < cells.length; i++) {
    final h = cells[i];
    if (h.isEmpty || !freeFor(i)) continue;
    if (m.debit == null && (h.contains('debit') || h.contains('withdrawal') || h.contains('paid out'))) {
      m.debit = i;
      continue;
    }
    if (m.credit == null && (h.contains('credit') || h.contains('deposit') || h.contains('paid in'))) {
      m.credit = i;
    }
  }
  if (!m.splitAmounts) {
    for (var i = 0; i < cells.length; i++) {
      final h = cells[i];
      if (h.isEmpty || !freeFor(i)) continue;
      if (h.contains('amount') && !h.contains('balance')) {
        m.amount = i;
        break;
      }
    }
  }
  for (var i = 0; i < cells.length; i++) {
    final h = cells[i];
    if (h.isEmpty || !freeFor(i)) continue;
    if (const ['ref', 'cheque', 'chq', 'utr'].any(h.contains)) {
      m.reference = i;
      break;
    }
  }
  return m;
}

// ---- date parsing ----------------------------------------------------------

enum DateOrder { dmy, mdy, ymd }

const _monthNames = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

int? _monthFromName(String s) {
  final k = s.toLowerCase();
  if (k.length < 3) return null;
  return _monthNames[k.substring(0, 3)];
}

DateTime? _mkDate(int year, int month, int day) {
  var y = year;
  if (y < 100) y += y < 70 ? 2000 : 1900;
  if (month < 1 || month > 12 || day < 1 || day > 31 || y < 1980 || y > 2100) return null;
  final dt = DateTime(y, month, day);
  if (dt.month != month || dt.day != day) return null; // rolled over (e.g. 31 Feb)
  return dt;
}

// The separator class carries an apostrophe so a shortened year written the
// way statements print it, "20 Aug '26", is read rather than skipped. A row
// whose date will not parse is dropped entirely, so this was the difference
// between a card statement importing and importing as nothing.
final _dateTokenRe = RegExp(r"^\s*([A-Za-z0-9]{1,9})[-/. ,']+([A-Za-z0-9]{1,9})[-/. ,']+([A-Za-z0-9]{1,4})");

/// Parse one date cell using the given day/month order for all-numeric dates.
/// Month names ("03 Jan 2025", "Jan 3, 2025") parse regardless of order.
DateTime? parseFlexibleDate(String raw, DateOrder order) {
  final match = _dateTokenRe.firstMatch(raw.trim());
  if (match == null) return null;
  final t = [match.group(1)!, match.group(2)!, match.group(3)!];
  final nums = [for (final s in t) int.tryParse(s)];

  // Month-name forms.
  final midMonth = _monthFromName(t[1]);
  if (nums[1] == null && midMonth != null && nums[0] != null && nums[2] != null) {
    // "03 Jan 2025" or "2025 Jan 03"
    return t[0].length == 4 ? _mkDate(nums[0]!, midMonth, nums[2]!) : _mkDate(nums[2]!, midMonth, nums[0]!);
  }
  final firstMonth = _monthFromName(t[0]);
  if (nums[0] == null && firstMonth != null && nums[1] != null && nums[2] != null) {
    // "Jan 3, 2025"
    return _mkDate(nums[2]!, firstMonth, nums[1]!);
  }
  if (nums[0] == null || nums[1] == null || nums[2] == null) return null;

  // All numeric: a 4-digit first token is unambiguously year-first.
  if (t[0].length == 4 || order == DateOrder.ymd) {
    return _mkDate(nums[0]!, nums[1]!, nums[2]!);
  }
  return order == DateOrder.dmy
      ? _mkDate(nums[2]!, nums[1]!, nums[0]!)
      : _mkDate(nums[2]!, nums[0]!, nums[1]!);
}

/// Pick the numeric day/month order that parses the most sample cells.
///
/// A file whose dates all fall on the 12th or earlier fits either order
/// equally, and then only the reader's own convention can break the tie:
/// [prefer], which the import screen takes from the phone (see
/// [dateOrderForLocale]). It defaults to day-first, the Indian and
/// most-banks convention.
DateOrder detectDateOrder(Iterable<String> samples, {DateOrder prefer = DateOrder.dmy}) {
  final score = {for (final o in DateOrder.values) o: 0};
  for (final s in samples) {
    for (final o in DateOrder.values) {
      if (parseFlexibleDate(s, o) != null) score[o] = score[o]! + 1;
    }
  }
  var best = prefer;
  for (final o in const [DateOrder.dmy, DateOrder.ymd, DateOrder.mdy]) {
    if (score[o]! > score[best]!) best = o;
  }
  return best;
}

/// The numeric date order people in [locale] write by default. Of the
/// English variants the app formats dates in, only the United States puts the
/// month first; everywhere else the day comes first. A year-first date needs
/// no preference, as its four-digit year gives it away.
DateOrder dateOrderForLocale(String locale) {
  final parts = locale.split(RegExp('[_-]'));
  return parts.length > 1 && parts[1].toUpperCase() == 'US' ? DateOrder.mdy : DateOrder.dmy;
}

// ---- amount parsing --------------------------------------------------------

final _crRe = RegExp(r'(^|\s)cr\.?(\s|$)', caseSensitive: false);
final _drRe = RegExp(r'(^|\s)dr\.?(\s|$)', caseSensitive: false);

// Everything that can sit beside a figure to say what currency it is in:
// any currency sign, with the one or two letters some write before it (S$,
// HK$, CN¥, R$), and every ISO code the app knows plus a few that banks print
// (Rs., Rp, RM, KSh). Codes match only as whole words, so a cell such as
// "UPI/509" is still not mistaken for an amount of 509.
final _currencyRe = RegExp(
  '(?:[A-Za-z]{0,2}\\p{Sc})|'
  '(?<![A-Za-z])(?:${{
    ...kCurrencies.map((c) => c.code),
    'RS',
    'RP',
    'RM',
    'KSH'
  }.join('|')})\\.?(?![A-Za-z])',
  caseSensitive: false,
  unicode: true,
);

// A decimal part written with the other mark: "12,50" when the file uses
// '.', "12.50" when it uses ','. Grouping never leaves one or two digits
// after the last separator, so this can only be a misread decimal.
final _strayCommaDecimalRe = RegExp(r',\d{1,2}$');
final _strayPointDecimalRe = RegExp(r'\.\d{1,2}$');

/// Parse an amount cell to a signed double. "1,234.56 Dr", "(500)", "-500",
/// "500-", "₹ 1,000 CR", "Rs.250", "\$1,234.56", "USD 99" all work; returns
/// null for non-numeric text.
///
/// [decimalSeparator] is the file's decimal mark: with ',' the figure
/// "1.234,56 €" reads as 1234.56. A figure that plainly carries the other
/// mark's decimals ("12,50" read with '.') returns null rather than a number
/// a hundred times too large: an unreadable row is flagged on the review
/// screen, while a wrong amount would be imported without a word.
double? parseAmountText(String raw, {String decimalSeparator = '.'}) {
  var t = raw.trim();
  if (t.isEmpty) return null;
  var negative = false;
  var positive = false;
  if (_drRe.hasMatch(t)) negative = true;
  if (_crRe.hasMatch(t)) positive = true;
  if (t.startsWith('(') && t.endsWith(')')) negative = true;
  t = t.replaceAll(_drRe, ' ').replaceAll(_crRe, ' ').replaceAll(_currencyRe, '');
  // Spaces, non-breaking spaces and apostrophes group digits in French and
  // Swiss figures (1 234,56 and 1'234.56); none of them ever mark decimals.
  t = t.replaceAll(RegExp(r"[()\s'’]"), '').replaceAll('−', '-');
  if (decimalSeparator == ',') {
    if (_strayPointDecimalRe.hasMatch(t)) return null;
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else {
    if (_strayCommaDecimalRe.hasMatch(t)) return null;
    t = t.replaceAll(',', '');
  }
  if (t.startsWith('-')) {
    negative = true;
    t = t.substring(1);
  } else if (t.startsWith('+')) {
    t = t.substring(1);
  } else if (t.endsWith('-')) {
    // German and Dutch statements print a debit as "1.234,56-".
    negative = true;
    t = t.substring(0, t.length - 1);
  }
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null) return null;
  if (negative && !positive) return -v.abs();
  if (positive) return v.abs();
  return v;
}

final _numberCoreRe = RegExp(r"\d[\d.,'’\s]*\d|\d");

/// The decimal mark a column of amounts is written with: ',' or '.'.
///
/// Each figure votes only when its own shape settles the question:
///  * both marks present: the one that comes last is the decimal mark
///    (1.234,56 and 1,234.56, and India's 1,23,456.78);
///  * one mark, repeated: it is grouping, so the decimal mark is the other
///    (1.234.567 or 1,234,567);
///  * one mark, once, followed by one, two, or four or more digits: it is the
///    decimal mark (12,50 or 12.5).
/// A lone mark followed by exactly three digits (1,234 or 1.234) could be
/// either, a thousand or a Kuwaiti dinar and change, so it does not vote.
/// The column goes to ',' only when commas win outright; with no votes, or a
/// tie, it stays '.', which is how every Indian, US and British file reads.
String detectDecimalSeparator(Iterable<String> samples) {
  var comma = 0, point = 0;
  for (final raw in samples) {
    final m = _numberCoreRe.firstMatch(raw.replaceAll(_currencyRe, ''));
    if (m == null) continue;
    final core = m.group(0)!.replaceAll(RegExp(r"[\s'’]"), '');
    final lastComma = core.lastIndexOf(',');
    final lastPoint = core.lastIndexOf('.');
    if (lastComma >= 0 && lastPoint >= 0) {
      lastComma > lastPoint ? comma++ : point++;
      continue;
    }
    final mark = lastComma >= 0 ? ',' : (lastPoint >= 0 ? '.' : null);
    if (mark == null) continue;
    final repeated = core.indexOf(mark) != core.lastIndexOf(mark);
    final decimals = core.length - core.lastIndexOf(mark) - 1;
    if (!repeated && decimals == 3) continue; // 1,234 or 1.234: could be either
    // A repeated mark groups digits; a single one marks the decimals.
    final commaIsDecimal = (mark == ',') != repeated;
    if (commaIsDecimal) {
      comma++;
    } else {
      point++;
    }
  }
  return comma > point ? ',' : '.';
}

/// The decimal mark of the figures in [m]'s amount columns (amount, debit,
/// credit and balance) across [rows]. Description and reference cells are
/// left out: "Invoice 12,50" in a note says nothing about how the amounts are
/// written.
String detectMappingDecimalSeparator(List<List<String>> rows, ColumnMapping m) {
  final cols = [m.amount, m.debit, m.credit, m.balance].whereType<int>().toList();
  return detectDecimalSeparator([
    for (final r in rows.take(200))
      for (final c in cols)
        if (c < r.length) r[c],
  ]);
}

// ---- row building ----------------------------------------------------------

/// One statement row after mapping: parsed values plus the raw cells, so the
/// review screen can show and let the user fix anything.
class ImportRowDraft {
  DateTime? date;
  String description;
  double? amount; // signed: money in > 0, money out < 0
  String reference;
  double? balance; // running balance after this row (reconciliation only)
  final int sourceRow;
  ImportRowDraft({
    required this.sourceRow,
    this.date,
    this.description = '',
    this.amount,
    this.reference = '',
    this.balance,
  });

  bool get parseable => date != null && amount != null && amount!.abs() > 0.004;
}

/// Summary/footer lines that end a transaction record instead of extending it.
final _summaryLineRe = RegExp(
    r'(opening|closing|available)\s+balance|grand\s+total|^\s*total\b|'
    r'carried\s+forward|brought\s+forward|statement\s+summary|'
    r'page\s+\d+\s*(of|/)\s*\d+|end\s+of\s+statement',
    caseSensitive: false);

/// Run the mapped columns over the grid's data rows, assembling logical
/// transaction records: a row with a parseable date STARTS a record; dateless
/// rows EXTEND the current one — wrapped description text is appended, and an
/// amount/reference lands on a record that doesn't have one yet (bank PDFs
/// often print one transaction across two text lines, date first, amount on
/// the continuation). Summary/footer lines close the record so trailing page
/// noise never leaks into a transaction.
List<ImportRowDraft> buildImportRows(StatementGrid grid, ColumnMapping m, DateOrder order) {
  String cell(List<String> row, int? i) => (i == null || i < 0 || i >= row.length) ? '' : row[i];
  final decimal = m.decimalSeparator ?? detectMappingDecimalSeparator(grid.dataRows, m);
  double? parse(String raw) => parseAmountText(raw, decimalSeparator: decimal);
  double? amountOf(List<String> row) {
    if (m.splitAmounts) {
      final debit = parse(cell(row, m.debit));
      final credit = parse(cell(row, m.credit));
      if (credit != null && credit.abs() > 0.004) return credit.abs();
      if (debit != null && debit.abs() > 0.004) return -debit.abs();
      return null;
    }
    final v = parse(cell(row, m.amount));
    if (v == null || v.abs() <= 0.004) return null;
    // A direction column overrules the figure's own sign, since a statement
    // that prints one carries unsigned amounts.
    final out = m.direction != null ? isMoneyOutCell(cell(row, m.direction)) : null;
    if (out == null) return v;
    return out ? -v.abs() : v.abs();
  }

  final out = <ImportRowDraft>[];
  ImportRowDraft? current;
  final data = grid.dataRows;
  for (var i = 0; i < data.length; i++) {
    final row = data[i];
    final date = parseFlexibleDate(cell(row, m.date), order);
    final amount = amountOf(row);
    final desc = cell(row, m.description);
    final ref = cell(row, m.reference);
    final balance = m.balance != null ? parse(cell(row, m.balance)) : null;

    if (date != null) {
      current = ImportRowDraft(
        sourceRow: grid.headerRow + 1 + i,
        date: date,
        description: desc,
        amount: amount,
        reference: ref,
        balance: balance,
      );
      out.add(current);
      continue;
    }

    // Dateless: a continuation of the current record, or noise.
    if (current == null) continue;
    if (_summaryLineRe.hasMatch(row.join(' '))) {
      current = null; // table (or page section) ended — stop extending
      continue;
    }
    if (amount != null && current.amount == null) current.amount = amount;
    if (balance != null && current.balance == null) current.balance = balance;
    if (desc.isNotEmpty) {
      current.description = current.description.isEmpty ? desc : '${current.description} $desc';
    }
    if (ref.isNotEmpty && current.reference.isEmpty) current.reference = ref;
  }
  return out;
}

// ---- dedupe fingerprint ----------------------------------------------------

String _two(int n) => n.toString().padLeft(2, '0');

/// Stable identity of a statement row: account + date + signed amount + the
/// normalized head of its reference/description. Stored as `importKey` on
/// imported transactions and recomputed for existing ones, so re-importing the
/// same statement (or an overlapping period) flags duplicates.
String importFingerprint({
  required String accountId,
  required DateTime date,
  required double amount,
  required String refOrDesc,
}) {
  var norm = refOrDesc.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (norm.length > 40) norm = norm.substring(0, 40);
  final d = '${date.year}-${_two(date.month)}-${_two(date.day)}';
  return '$accountId|$d|${amount.toStringAsFixed(2)}|$norm';
}
