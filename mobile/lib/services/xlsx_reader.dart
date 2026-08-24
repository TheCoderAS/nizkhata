// Direct .xlsx reader: an xlsx is a zip of XML parts. We read the parts we
// need (shared strings, styles for date detection, the worksheets) ourselves,
// because the `excel` package throws on many real-world files (openpyxl and
// several bank exports included). Returns the busiest sheet as a string grid.

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class XlsxError implements Exception {
  final String message;
  XlsxError(this.message);
  @override
  String toString() => message;
}

/// Read an .xlsx (zip) into rows of trimmed cell strings — the sheet with the
/// most non-empty cells. Date-formatted numeric cells become ISO dates.
List<List<String>> readXlsx(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw XlsxError('Not a readable .xlsx file.');
  }
  final files = <String, Uint8List>{};
  for (final f in archive.files) {
    if (f.isFile) files[f.name] = f.content as Uint8List;
  }

  final shared = _readSharedStrings(files['xl/sharedStrings.xml']);
  final dateStyles = _readDateStyles(files['xl/styles.xml']);
  final date1904 = _read1904(files['xl/workbook.xml']);

  // Every worksheet part, parsed; keep the busiest.
  List<List<String>>? best;
  var bestCount = 0;
  final sheetNames = files.keys
      .where((n) => n.startsWith('xl/worksheets/') && n.endsWith('.xml'))
      .toList()
    ..sort();
  for (final name in sheetNames) {
    final rows = _readSheet(files[name]!, shared, dateStyles, date1904);
    var count = 0;
    for (final r in rows) {
      for (final c in r) {
        if (c.isNotEmpty) count++;
      }
    }
    if (count > bestCount) {
      bestCount = count;
      best = rows;
    }
  }
  if (best == null || bestCount == 0) throw XlsxError('The Excel file has no data.');
  return best;
}

List<String> _readSharedStrings(Uint8List? data) {
  if (data == null) return const [];
  final doc = XmlDocument.parse(String.fromCharCodes(data));
  final out = <String>[];
  for (final si in doc.findAllElements('si')) {
    // Concatenate all <t> runs inside this shared-string item.
    final buf = StringBuffer();
    for (final t in si.findAllElements('t')) {
      buf.write(t.innerText);
    }
    out.add(buf.toString());
  }
  return out;
}

// Builtin numFmt ids that render as dates/times.
const _builtinDateFmts = {
  14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47,
  27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 50, 51, 52, 53, 54, 55, 56, 57, 58,
};

/// Style indices (cellXfs order) whose number format is a date.
Set<int> _readDateStyles(Uint8List? data) {
  final result = <int>{};
  if (data == null) return result;
  final doc = XmlDocument.parse(String.fromCharCodes(data));

  // Custom numFmt id -> is-date.
  final customDate = <int>{};
  for (final nf in doc.findAllElements('numFmt')) {
    final id = int.tryParse(nf.getAttribute('numFmtId') ?? '');
    final code = nf.getAttribute('formatCode') ?? '';
    if (id != null && _looksLikeDateFormat(code)) customDate.add(id);
  }

  final cellXfs = doc.findAllElements('cellXfs').firstOrNull;
  if (cellXfs == null) return result;
  var idx = 0;
  for (final xf in cellXfs.findElements('xf')) {
    final fmtId = int.tryParse(xf.getAttribute('numFmtId') ?? '');
    if (fmtId != null && (_builtinDateFmts.contains(fmtId) || customDate.contains(fmtId))) {
      result.add(idx);
    }
    idx++;
  }
  return result;
}

bool _looksLikeDateFormat(String code) {
  final f = code
      .replaceAll(RegExp(r'"[^"]*"'), '')
      .replaceAll(RegExp(r'\[[^\]]*\]'), '')
      .toLowerCase();
  return f.contains('y') || f.contains('d') || (f.contains('m') && f.contains(':') == false && f.contains('mmm'));
}

bool _read1904(Uint8List? data) {
  if (data == null) return false;
  try {
    final doc = XmlDocument.parse(String.fromCharCodes(data));
    final pr = doc.findAllElements('workbookPr').firstOrNull;
    final v = pr?.getAttribute('date1904');
    return v == '1' || v == 'true';
  } catch (_) {
    return false;
  }
}

List<List<String>> _readSheet(
    Uint8List data, List<String> shared, Set<int> dateStyles, bool date1904) {
  final doc = XmlDocument.parse(String.fromCharCodes(data));
  final rowsOut = <List<String>>[];
  for (final row in doc.findAllElements('row')) {
    final cells = <int, String>{};
    var maxCol = -1;
    var autoCol = 0;
    for (final c in row.findElements('c')) {
      final ref = c.getAttribute('r');
      final col = ref != null ? _colOf(ref) : autoCol;
      autoCol = col + 1;
      final type = c.getAttribute('t');
      String text;
      if (type == 's') {
        final v = c.findElements('v').firstOrNull?.innerText;
        final idx = int.tryParse(v ?? '');
        text = (idx != null && idx >= 0 && idx < shared.length) ? shared[idx] : '';
      } else if (type == 'inlineStr') {
        final buf = StringBuffer();
        for (final t in c.findAllElements('t')) {
          buf.write(t.innerText);
        }
        text = buf.toString();
      } else if (type == 'str') {
        text = c.findElements('v').firstOrNull?.innerText ?? '';
      } else if (type == 'b') {
        text = (c.findElements('v').firstOrNull?.innerText == '1') ? 'TRUE' : 'FALSE';
      } else {
        // Numeric (or date).
        final v = c.findElements('v').firstOrNull?.innerText;
        if (v == null || v.isEmpty) {
          text = '';
        } else {
          final styleIdx = int.tryParse(c.getAttribute('s') ?? '');
          final num = double.tryParse(v);
          if (num != null && styleIdx != null && dateStyles.contains(styleIdx)) {
            text = _serialToIso(num, date1904) ?? v;
          } else if (num != null) {
            text = num == num.roundToDouble() ? num.round().toString() : num.toString();
          } else {
            text = v;
          }
        }
      }
      final trimmed = text.trim();
      if (trimmed.isNotEmpty) {
        cells[col] = trimmed;
        if (col > maxCol) maxCol = col;
      }
    }
    if (cells.isEmpty) continue;
    final list = List<String>.filled(maxCol + 1, '', growable: true);
    cells.forEach((k, v) => list[k] = v);
    rowsOut.add(list);
  }
  // Pad to a uniform width.
  var width = 0;
  for (final r in rowsOut) {
    if (r.length > width) width = r.length;
  }
  for (final r in rowsOut) {
    while (r.length < width) {
      r.add('');
    }
  }
  return rowsOut;
}

/// Column index from a cell ref like "AB12" → 27.
int _colOf(String ref) {
  var col = 0;
  for (var i = 0; i < ref.length; i++) {
    final ch = ref.codeUnitAt(i);
    if (ch >= 65 && ch <= 90) {
      col = col * 26 + (ch - 64);
    } else if (ch >= 97 && ch <= 122) {
      col = col * 26 + (ch - 96);
    } else {
      break;
    }
  }
  return col - 1;
}

String? _serialToIso(double serial, bool date1904) {
  if (serial < 1 || serial > 2958465) return null;
  final epoch = date1904 ? DateTime.utc(1904, 1, 1) : DateTime.utc(1899, 12, 30);
  final dt = epoch.add(Duration(days: serial.floor()));
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
