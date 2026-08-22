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
import 'package:excel/excel.dart' as xl;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// What the picked file turned out to be (by content sniffing, not extension).
enum StatementKind { csv, excel, pdf, html }

/// The PDF is encrypted: no password was given, or the given one is wrong.
class StatementPasswordRequired implements Exception {
  final bool wrongPassword;
  StatementPasswordRequired({required this.wrongPassword});
  @override
  String toString() =>
      wrongPassword ? 'Incorrect password.' : 'This PDF is password-protected.';
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
  List<List<String>> get dataRows =>
      headerRow + 1 >= rows.length ? const [] : rows.sublist(headerRow + 1);
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
    // OLE2 compound file: a legacy .xls binary — or a password-protected .xlsx,
    // which is stored in this same container. Neither can be opened on-device.
    throw StatementUnsupported(
        'This file is a legacy or password-protected Excel document, which '
        "can't be opened on-device. Please export the statement as CSV or PDF "
        '(or re-save it as an unprotected .xlsx) and try again.');
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

String _detectDelimiter(String text) {
  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).take(20).toList();
  var best = ',';
  var bestCount = -1;
  for (final d in const [',', ';', '\t', '|']) {
    var count = 0;
    for (final l in lines) {
      count += d.allMatches(l).length;
    }
    if (count > bestCount) {
      bestCount = count;
      best = d;
    }
  }
  return best;
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
  xl.Excel workbook;
  try {
    workbook = xl.Excel.decodeBytes(bytes);
  } catch (_) {
    throw StatementUnsupported(
        "This Excel file couldn't be read. If it's password-protected, export "
        'the statement as CSV or PDF instead.');
  }
  // Pick the sheet with the most non-empty cells.
  xl.Sheet? bestSheet;
  var bestCells = -1;
  for (final sheet in workbook.tables.values) {
    var cells = 0;
    for (final row in sheet.rows) {
      for (final c in row) {
        if (c != null && _cellText(c.value).isNotEmpty) cells++;
      }
    }
    if (cells > bestCells) {
      bestCells = cells;
      bestSheet = sheet;
    }
  }
  if (bestSheet == null || bestCells <= 0) {
    throw StatementUnsupported('The Excel file has no data.');
  }
  final rows = <List<String>>[];
  for (final raw in bestSheet.rows) {
    final cells = [for (final c in raw) _cellText(c?.value)];
    if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
  }
  _padRows(rows);
  return StatementGrid(kind: StatementKind.excel, rows: rows, headerRow: detectHeaderRow(rows));
}

String _two(int n) => n.toString().padLeft(2, '0');

String _cellText(xl.CellValue? v) {
  if (v == null) return '';
  if (v is xl.TextCellValue) return v.value.toString().trim();
  if (v is xl.IntCellValue) return v.value.toString();
  if (v is xl.DoubleCellValue) return v.value.toString();
  if (v is xl.BoolCellValue) return v.value.toString();
  if (v is xl.DateCellValue) return '${v.year}-${_two(v.month)}-${_two(v.day)}';
  if (v is xl.DateTimeCellValue) return '${v.year}-${_two(v.month)}-${_two(v.day)}';
  if (v is xl.TimeCellValue) return '';
  if (v is xl.FormulaCellValue) return '';
  return v.toString().trim();
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
      throw StatementUnsupported(
          'No transaction table was found in this PDF. If the statement is a '
          'scanned image, export a CSV from your bank instead.');
    }
    return StatementGrid(kind: StatementKind.pdf, rows: rows, headerRow: 0);
  } finally {
    doc.dispose();
  }
}

/// Rebuild the transaction table from positioned PDF text: find the header
/// line by keywords, derive column boundaries from the x-positions of its
/// word clusters, then assign every following line's words into those columns.
List<List<String>>? _pdfLinesToGrid(List<TextLine> lines) {
  // Find the most header-like line (≥2 keyword groups matched).
  var headerIdx = -1;
  var headerScoreBest = 1;
  for (var i = 0; i < lines.length; i++) {
    final score = headerScore(_lineWordTexts(lines[i]));
    if (score > headerScoreBest) {
      headerScoreBest = score;
      headerIdx = i;
      if (score >= 4) break; // unmistakable header — stop early
    }
  }
  if (headerIdx < 0) return null;

  final headerLine = lines[headerIdx];
  final clusters = _clusterWords(headerLine);
  if (clusters.length < 2) return null;

  // Boundary between column i and i+1: midpoint of the gap between clusters.
  final boundaries = <double>[];
  for (var i = 0; i + 1 < clusters.length; i++) {
    boundaries.add((clusters[i].right + clusters[i + 1].left) / 2);
  }

  final headerCells = [for (final c in clusters) c.text];
  final headerNorm = _normText(headerCells.join(' '));
  final rows = <List<String>>[headerCells];

  for (var i = headerIdx + 1; i < lines.length; i++) {
    final line = lines[i];
    // Skip repeated page headers (same header re-printed on later pages).
    final lineNorm = _normText(line.text);
    if (lineNorm == headerNorm) continue;
    final cells = List<String>.filled(clusters.length, '');
    for (final w in line.wordCollection) {
      final text = w.text.trim();
      if (text.isEmpty) continue;
      final cx = w.bounds.left + w.bounds.width / 2;
      var col = boundaries.length; // default: last column
      for (var b = 0; b < boundaries.length; b++) {
        if (cx < boundaries[b]) {
          col = b;
          break;
        }
      }
      cells[col] = cells[col].isEmpty ? text : '${cells[col]} $text';
    }
    if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
  }
  return rows.length > 1 ? rows : null;
}

List<String> _lineWordTexts(TextLine line) =>
    [for (final w in line.wordCollection) w.text.trim()];

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
  int? reference;
  ColumnMapping({this.date, this.description, this.amount, this.debit, this.credit, this.reference});

  /// Two-column (debit/credit) mode vs single-amount mode.
  bool get splitAmounts => debit != null || credit != null;
  bool get complete => date != null && (amount != null || splitAmounts);
}

/// Best-guess mapping from header labels. The user can override on-screen.
ColumnMapping suggestMapping(List<String> header) {
  final m = ColumnMapping();
  final cells = [for (final h in header) h.toLowerCase()];

  bool freeFor(int i) =>
      i != m.date && i != m.description && i != m.debit && i != m.credit && i != m.amount && i != m.reference;

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
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
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

final _dateTokenRe = RegExp(r'^\s*([A-Za-z0-9]{1,9})[-/. ,]+([A-Za-z0-9]{1,9})[-/. ,]+([A-Za-z0-9]{1,4})');

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
    return t[0].length == 4
        ? _mkDate(nums[0]!, midMonth, nums[2]!)
        : _mkDate(nums[2]!, midMonth, nums[0]!);
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
/// Ties prefer day-first (the Indian/most-banks convention).
DateOrder detectDateOrder(Iterable<String> samples) {
  var dmy = 0, mdy = 0, ymd = 0;
  for (final s in samples) {
    if (parseFlexibleDate(s, DateOrder.dmy) != null) dmy++;
    if (parseFlexibleDate(s, DateOrder.mdy) != null) mdy++;
    if (parseFlexibleDate(s, DateOrder.ymd) != null) ymd++;
  }
  if (dmy >= mdy && dmy >= ymd) return DateOrder.dmy;
  if (ymd >= mdy) return DateOrder.ymd;
  return DateOrder.mdy;
}

// ---- amount parsing --------------------------------------------------------

final _crRe = RegExp(r'(^|\s)cr\.?(\s|$)', caseSensitive: false);
final _drRe = RegExp(r'(^|\s)dr\.?(\s|$)', caseSensitive: false);
final _currencyRe = RegExp(r'(?:inr|rs\.?|₹)', caseSensitive: false);

/// Parse an amount cell to a signed double. "1,234.56 Dr", "(500)", "-500",
/// "₹ 1,000 CR", "Rs.250" all work; returns null for non-numeric text.
double? parseAmountText(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return null;
  var negative = false;
  var positive = false;
  if (_drRe.hasMatch(t)) negative = true;
  if (_crRe.hasMatch(t)) positive = true;
  if (t.startsWith('(') && t.endsWith(')')) negative = true;
  t = t.replaceAll(_drRe, ' ').replaceAll(_crRe, ' ').replaceAll(_currencyRe, '');
  t = t.replaceAll(RegExp(r'[,()\s]'), '');
  if (t.startsWith('-')) {
    negative = true;
    t = t.substring(1);
  } else if (t.startsWith('+')) {
    t = t.substring(1);
  }
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null) return null;
  if (negative && !positive) return -v.abs();
  if (positive) return v.abs();
  return v;
}

// ---- row building ----------------------------------------------------------

/// One statement row after mapping: parsed values plus the raw cells, so the
/// review screen can show and let the user fix anything.
class ImportRowDraft {
  DateTime? date;
  String description;
  double? amount; // signed: money in > 0, money out < 0
  String reference;
  final int sourceRow;
  ImportRowDraft({
    required this.sourceRow,
    this.date,
    this.description = '',
    this.amount,
    this.reference = '',
  });

  bool get parseable => date != null && amount != null && amount!.abs() > 0.004;
}

/// Run the mapped columns over the grid's data rows. Rows with no date and no
/// amount but with description text are treated as wrapped continuation lines
/// and appended to the previous row's description.
List<ImportRowDraft> buildImportRows(StatementGrid grid, ColumnMapping m, DateOrder order) {
  String cell(List<String> row, int? i) => (i == null || i < 0 || i >= row.length) ? '' : row[i];
  final out = <ImportRowDraft>[];
  final data = grid.dataRows;
  for (var i = 0; i < data.length; i++) {
    final row = data[i];
    final date = parseFlexibleDate(cell(row, m.date), order);
    double? amount;
    if (m.splitAmounts) {
      final debit = parseAmountText(cell(row, m.debit));
      final credit = parseAmountText(cell(row, m.credit));
      if (credit != null && credit.abs() > 0.004) {
        amount = credit.abs();
      } else if (debit != null && debit.abs() > 0.004) {
        amount = -debit.abs();
      }
    } else {
      amount = parseAmountText(cell(row, m.amount));
    }
    final desc = cell(row, m.description);
    if (date == null && amount == null) {
      // Continuation of a wrapped description, or table noise.
      if (desc.isNotEmpty && out.isNotEmpty) {
        final prev = out.last;
        prev.description = prev.description.isEmpty ? desc : '${prev.description} $desc';
      }
      continue;
    }
    out.add(ImportRowDraft(
      sourceRow: grid.headerRow + 1 + i,
      date: date,
      description: desc,
      amount: amount,
      reference: cell(row, m.reference),
    ));
  }
  return out;
}

// ---- dedupe fingerprint ----------------------------------------------------

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
