// Minimal legacy Excel (.xls, BIFF5/BIFF8) reader — just enough to pull a
// bank statement's cell grid out on-device, since no maintained pure-Dart
// package reads the old binary format. Parses the OLE2/CFB container, walks
// the Workbook stream's BIFF records (SST with CONTINUE splits, LABELSST,
// LABEL, NUMBER, RK, MULRK, FORMULA cached results) and converts
// date-formatted serial numbers to ISO dates via XF/FORMAT records.

import 'dart:typed_data';

/// The workbook is encrypted (legacy XOR/RC4, or an OOXML EncryptedPackage
/// stored in a CFB container) — not decryptable on-device.
class XlsPasswordProtected implements Exception {}

/// The file isn't a readable BIFF workbook.
class XlsUnreadable implements Exception {
  final String message;
  XlsUnreadable(this.message);
  @override
  String toString() => message;
}

/// Decode a legacy .xls into rows of cell text (the sheet with the most
/// non-empty cells wins). Throws [XlsPasswordProtected] or [XlsUnreadable].
List<List<String>> decodeXls(Uint8List bytes) {
  final cfb = _Cfb(bytes);
  if (cfb.hasStream('EncryptedPackage')) throw XlsPasswordProtected();
  final workbook = cfb.readStreamNamed('Workbook') ?? cfb.readStreamNamed('Book');
  if (workbook == null) {
    throw XlsUnreadable('No Excel workbook stream found in this file.');
  }
  return _BiffParser(workbook).parse();
}

// ---- OLE2 / Compound File Binary container ---------------------------------

const _endOfChain = 0xFFFFFFFE;
const _freeSect = 0xFFFFFFFF;

class _Cfb {
  final Uint8List b;
  late final ByteData _d = ByteData.sublistView(b);
  late final int _sectorSize;
  late final int _miniSectorSize;
  late final int _miniCutoff;
  late final List<int> _fat;
  late final List<int> _miniFat;
  final List<_DirEntry> _entries = [];
  Uint8List _miniStream = Uint8List(0);

  _Cfb(this.b) {
    if (b.length < 512) throw XlsUnreadable('File too small to be an Excel file.');
    _sectorSize = 1 << _u16(30);
    _miniSectorSize = 1 << _u16(32);
    _miniCutoff = _u32(56);
    if (_sectorSize < 128 || _sectorSize > 65536) {
      throw XlsUnreadable('Corrupt Excel container.');
    }
    _fat = _readFat();
    _readDirectory();
    _miniFat = _readMiniFat();
  }

  int _u16(int off) => _d.getUint16(off, Endian.little);
  int _u32(int off) => _d.getUint32(off, Endian.little);

  int _sectorOffset(int sid) => (sid + 1) * _sectorSize;

  List<int> _readFat() {
    final fatSectors = <int>[];
    for (var i = 0; i < 109; i++) {
      final sid = _u32(76 + i * 4);
      if (sid != _freeSect && sid != _endOfChain) fatSectors.add(sid);
    }
    // DIFAT chain for very large files.
    var difat = _u32(68);
    var guard = 0;
    final perDifat = _sectorSize ~/ 4 - 1;
    while (difat != _endOfChain && difat != _freeSect && guard++ < 4096) {
      final off = _sectorOffset(difat);
      for (var i = 0; i < perDifat; i++) {
        final sid = _u32(off + i * 4);
        if (sid != _freeSect && sid != _endOfChain) fatSectors.add(sid);
      }
      difat = _u32(off + perDifat * 4);
    }
    final fat = <int>[];
    final perFat = _sectorSize ~/ 4;
    for (final sid in fatSectors) {
      final off = _sectorOffset(sid);
      if (off + _sectorSize > b.length) continue;
      for (var i = 0; i < perFat; i++) {
        fat.add(_u32(off + i * 4));
      }
    }
    return fat;
  }

  List<int> _readMiniFat() {
    final out = <int>[];
    var sid = _u32(60);
    var guard = 0;
    final perFat = _sectorSize ~/ 4;
    while (sid != _endOfChain && sid != _freeSect && guard++ < 65536) {
      final off = _sectorOffset(sid);
      if (off + _sectorSize > b.length) break;
      for (var i = 0; i < perFat; i++) {
        out.add(_u32(off + i * 4));
      }
      sid = sid < _fat.length ? _fat[sid] : _endOfChain;
    }
    return out;
  }

  Uint8List _readChain(int start, int size) {
    final out = BytesBuilder();
    var sid = start;
    var guard = 0;
    while (sid != _endOfChain && sid != _freeSect && guard++ < 1 << 20) {
      final off = _sectorOffset(sid);
      if (off >= b.length) break;
      final end = (off + _sectorSize) > b.length ? b.length : off + _sectorSize;
      out.add(b.sublist(off, end));
      sid = sid < _fat.length ? _fat[sid] : _endOfChain;
    }
    final all = out.toBytes();
    return size >= 0 && size <= all.length ? all.sublist(0, size) : all;
  }

  Uint8List _readMiniChain(int start, int size) {
    final out = BytesBuilder();
    var sid = start;
    var guard = 0;
    while (sid != _endOfChain && sid != _freeSect && guard++ < 1 << 20) {
      final off = sid * _miniSectorSize;
      if (off >= _miniStream.length) break;
      final end = (off + _miniSectorSize) > _miniStream.length
          ? _miniStream.length
          : off + _miniSectorSize;
      out.add(_miniStream.sublist(off, end));
      sid = sid < _miniFat.length ? _miniFat[sid] : _endOfChain;
    }
    final all = out.toBytes();
    return size >= 0 && size <= all.length ? all.sublist(0, size) : all;
  }

  void _readDirectory() {
    final dirStart = _u32(48);
    final dir = _readChain(dirStart, -1);
    for (var off = 0; off + 128 <= dir.length; off += 128) {
      final d = ByteData.sublistView(dir, off, off + 128);
      final nameLen = d.getUint16(64, Endian.little);
      if (nameLen < 2 || nameLen > 64) continue;
      final chars = <int>[];
      for (var i = 0; i < nameLen - 2; i += 2) {
        chars.add(d.getUint16(i, Endian.little));
      }
      _entries.add(_DirEntry(
        String.fromCharCodes(chars),
        d.getUint8(66),
        d.getUint32(116, Endian.little),
        d.getUint32(120, Endian.little),
      ));
    }
    // The root entry's chain is the container for all mini streams.
    for (final e in _entries) {
      if (e.type == 5) {
        _miniStream = _readChain(e.start, e.size);
        break;
      }
    }
  }

  bool hasStream(String name) =>
      _entries.any((e) => e.type == 2 && e.name.toLowerCase() == name.toLowerCase());

  Uint8List? readStreamNamed(String name) {
    for (final e in _entries) {
      if (e.type != 2 || e.name.toLowerCase() != name.toLowerCase()) continue;
      return e.size < _miniCutoff ? _readMiniChain(e.start, e.size) : _readChain(e.start, e.size);
    }
    return null;
  }
}

class _DirEntry {
  final String name;
  final int type; // 1 storage, 2 stream, 5 root
  final int start;
  final int size;
  _DirEntry(this.name, this.type, this.start, this.size);
}

// ---- BIFF records ----------------------------------------------------------

class _BiffParser {
  final Uint8List s;
  late final ByteData _d = ByteData.sublistView(s);
  _BiffParser(this.s);

  bool _biff8 = true;
  bool _date1904 = false;
  final List<String> _sst = [];
  final List<int> _xfFormats = []; // XF index -> ifmt
  final Map<int, String> _customFormats = {}; // ifmt -> format string

  List<List<String>> parse() {
    // Pass 1 (workbook globals): SST, XF, FORMAT, DATEMODE, FILEPASS.
    // Pass 2: walk every sheet substream collecting cells.
    final sheets = <Map<int, Map<int, String>>>[];
    Map<int, Map<int, String>>? cells;
    int? pendingStringRow, pendingStringCol; // FORMULA with a cached string
    var pos = 0;
    var sawBof = false;
    while (pos + 4 <= s.length) {
      final id = _d.getUint16(pos, Endian.little);
      final len = _d.getUint16(pos + 2, Endian.little);
      final start = pos + 4;
      if (start + len > s.length) break;
      pos = start + len;
      switch (id) {
        case 0x0809: // BOF
          sawBof = true;
          if (len >= 2) {
            final ver = _d.getUint16(start, Endian.little);
            if (ver == 0x0500) _biff8 = false;
          }
          // A sheet substream begins: start a fresh cell map (the globals
          // substream produces an empty one that's discarded by the picker).
          cells = {};
          sheets.add(cells);
          break;
        case 0x002F: // FILEPASS — encrypted workbook
          throw XlsPasswordProtected();
        case 0x0022: // DATEMODE
          if (len >= 2) _date1904 = _d.getUint16(start, Endian.little) == 1;
          break;
        case 0x00FC: // SST (+ CONTINUE records)
          pos = _readSst(start, len, pos);
          break;
        case 0x00E0: // XF
          if (len >= 4) _xfFormats.add(_d.getUint16(start + 2, Endian.little));
          break;
        case 0x041E: // FORMAT
          _readFormat(start, len);
          break;
        case 0x00FD: // LABELSST
          if (len >= 10 && cells != null) {
            final idx = _d.getUint32(start + 6, Endian.little);
            if (idx < _sst.length) {
              _put(cells, _d.getUint16(start, Endian.little),
                  _d.getUint16(start + 2, Endian.little), _sst[idx]);
            }
          }
          break;
        case 0x0204: // LABEL (inline string)
        case 0x00D6: // RSTRING
          if (len >= 8 && cells != null) {
            final text = _readInlineString(start + 6, start + len);
            _put(cells, _d.getUint16(start, Endian.little),
                _d.getUint16(start + 2, Endian.little), text);
          }
          break;
        case 0x0203: // NUMBER
          if (len >= 14 && cells != null) {
            _putNumber(cells, _d.getUint16(start, Endian.little),
                _d.getUint16(start + 2, Endian.little),
                _d.getUint16(start + 4, Endian.little),
                _d.getFloat64(start + 6, Endian.little));
          }
          break;
        case 0x027E: // RK
          if (len >= 10 && cells != null) {
            _putNumber(cells, _d.getUint16(start, Endian.little),
                _d.getUint16(start + 2, Endian.little),
                _d.getUint16(start + 4, Endian.little),
                _decodeRk(_d.getUint32(start + 6, Endian.little)));
          }
          break;
        case 0x00BD: // MULRK
          if (len >= 10 && cells != null) {
            final row = _d.getUint16(start, Endian.little);
            final colFirst = _d.getUint16(start + 2, Endian.little);
            final count = (len - 6) ~/ 6;
            for (var i = 0; i < count; i++) {
              final off = start + 4 + i * 6;
              _putNumber(cells, row, colFirst + i, _d.getUint16(off, Endian.little),
                  _decodeRk(_d.getUint32(off + 2, Endian.little)));
            }
          }
          break;
        case 0x0006: // FORMULA — use the cached result
          if (len >= 22 && cells != null) {
            final row = _d.getUint16(start, Endian.little);
            final col = _d.getUint16(start + 2, Endian.little);
            final xf = _d.getUint16(start + 4, Endian.little);
            if (_d.getUint16(start + 12, Endian.little) == 0xFFFF) {
              final kind = _d.getUint8(start + 6);
              if (kind == 0) {
                // Cached string arrives in the next STRING record.
                pendingStringRow = row;
                pendingStringCol = col;
              } else if (kind == 1) {
                _put(cells, row, col, _d.getUint8(start + 8) == 1 ? 'TRUE' : 'FALSE');
              }
            } else {
              _putNumber(cells, row, col, xf, _d.getFloat64(start + 6, Endian.little));
            }
          }
          break;
        case 0x0207: // STRING (cached formula text)
          if (cells != null && pendingStringRow != null && pendingStringCol != null) {
            _put(cells, pendingStringRow, pendingStringCol,
                _readInlineString(start, start + len));
            pendingStringRow = null;
            pendingStringCol = null;
          }
          break;
        default:
          break;
      }
    }
    if (!sawBof) throw XlsUnreadable('Not a recognisable Excel workbook.');

    // Best sheet = most non-empty cells.
    Map<int, Map<int, String>>? best;
    var bestCount = 0;
    for (final sheet in sheets) {
      var count = 0;
      sheet.forEach((_, cols) => count += cols.length);
      if (count > bestCount) {
        bestCount = count;
        best = sheet;
      }
    }
    if (best == null || bestCount == 0) {
      throw XlsUnreadable('The Excel file has no readable cells.');
    }
    return _toGrid(best);
  }

  void _put(Map<int, Map<int, String>> cells, int row, int col, String v) {
    final t = v.trim();
    if (t.isEmpty) return;
    (cells[row] ??= {})[col] = t;
  }

  void _putNumber(Map<int, Map<int, String>> cells, int row, int col, int xf, double v) {
    if (_isDateXf(xf)) {
      final dt = _serialToDate(v);
      if (dt != null) {
        _put(cells, row, col,
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}');
        return;
      }
    }
    _put(cells, row, col, v == v.roundToDouble() ? v.round().toString() : v.toString());
  }

  double _decodeRk(int rk) {
    final f100 = rk & 0x01 != 0;
    final fInt = rk & 0x02 != 0;
    double v;
    if (fInt) {
      var i = rk >> 2;
      if (i & 0x20000000 != 0) i -= 0x40000000; // sign-extend 30 bits
      v = i.toDouble();
    } else {
      final bd = ByteData(8);
      bd.setUint32(4, rk & 0xFFFFFFFC, Endian.little);
      v = bd.getFloat64(0, Endian.little);
    }
    return f100 ? v / 100 : v;
  }

  // ---- dates ----

  static const _builtinDateFmts = {
    14, 15, 16, 17, 22, // date & date-time
    27, 28, 29, 30, 31, 32, 33, 34, 35, 36, // locale date variants
    50, 51, 52, 53, 54, 55, 56, 57, 58,
  };

  bool _isDateXf(int xf) {
    if (xf >= _xfFormats.length) return false;
    final ifmt = _xfFormats[xf];
    if (_builtinDateFmts.contains(ifmt)) return true;
    final custom = _customFormats[ifmt];
    if (custom == null) return false;
    // Strip quoted literals and [..] sections, then look for date letters.
    final f = custom
        .replaceAll(RegExp(r'"[^"]*"'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .toLowerCase();
    return f.contains('y') || (f.contains('d') && f.contains('m'));
  }

  DateTime? _serialToDate(double serial) {
    if (serial < 1 || serial > 2958465) return null; // outside year 9999
    final epoch = _date1904 ? DateTime.utc(1904, 1, 1) : DateTime.utc(1899, 12, 30);
    return epoch.add(Duration(days: serial.floor()));
  }

  void _readFormat(int start, int end0) {
    final end = start + end0;
    if (start + 2 > end) return;
    final ifmt = _d.getUint16(start, Endian.little);
    final text = _readInlineString(start + 2, end);
    if (text.isNotEmpty) _customFormats[ifmt] = text;
  }

  /// A string embedded in a record body: BIFF8 XLUnicodeString
  /// (cch u16, flags u8, chars) or a BIFF5 byte string (cch u16, bytes).
  String _readInlineString(int start, int end) {
    if (start + 2 > end) return '';
    final cch = _d.getUint16(start, Endian.little);
    if (!_biff8) {
      final from = start + 2;
      final to = from + cch > end ? end : from + cch;
      return String.fromCharCodes(s.sublist(from, to));
    }
    if (start + 3 > end) return '';
    final flags = _d.getUint8(start + 2);
    var p = start + 3;
    if (flags & 0x08 != 0 && p + 2 <= end) p += 2; // rich-run count (skip)
    if (flags & 0x04 != 0 && p + 4 <= end) p += 4; // ext size (skip)
    final wide = flags & 0x01 != 0;
    final chars = <int>[];
    for (var i = 0; i < cch; i++) {
      if (wide) {
        if (p + 2 > end) break;
        chars.add(_d.getUint16(p, Endian.little));
        p += 2;
      } else {
        if (p >= end) break;
        chars.add(_d.getUint8(p));
        p += 1;
      }
    }
    return String.fromCharCodes(chars);
  }

  /// SST: shared strings, possibly spanning CONTINUE records. Character data
  /// may split at a record boundary, where a fresh flags byte is emitted.
  /// Returns the stream position after the SST and all its CONTINUEs.
  int _readSst(int start, int len, int afterSst) {
    // Collect the SST record body plus all immediately following CONTINUEs.
    final spans = <_Span>[_Span(start, start + len)];
    var pos = afterSst;
    while (pos + 4 <= s.length && _d.getUint16(pos, Endian.little) == 0x003C) {
      final clen = _d.getUint16(pos + 2, Endian.little);
      if (pos + 4 + clen > s.length) break;
      spans.add(_Span(pos + 4, pos + 4 + clen));
      pos = pos + 4 + clen;
    }
    final r = _SpanReader(s, spans);
    r.skip(4); // total refs
    final unique = r.u32();
    for (var i = 0; i < unique && !r.done; i++) {
      final cch = r.u16();
      final flags = r.u8();
      var wide = flags & 0x01 != 0;
      final rich = flags & 0x08 != 0 ? r.u16() : 0;
      final ext = flags & 0x04 != 0 ? r.u32() : 0;
      final chars = <int>[];
      var remaining = cch;
      while (remaining > 0 && !r.done) {
        if (r.enteringNewSpan()) {
          // A split resumes with a fresh flags byte for the rest of the chars.
          wide = r.u8() & 0x01 != 0;
        }
        chars.add(wide ? r.u16NoCross() : r.u8());
        remaining--;
      }
      r.skip(rich * 4 + ext);
      _sst.add(String.fromCharCodes(chars));
    }
    return pos;
  }

  List<List<String>> _toGrid(Map<int, Map<int, String>> cells) {
    final rowKeys = cells.keys.toList()..sort();
    var maxCol = 0;
    for (final cols in cells.values) {
      for (final c in cols.keys) {
        if (c > maxCol) maxCol = c;
      }
    }
    if (maxCol > 255) maxCol = 255;
    final grid = <List<String>>[];
    for (final r in rowKeys) {
      final row = List<String>.filled(maxCol + 1, '');
      cells[r]!.forEach((c, v) {
        if (c <= maxCol) row[c] = v;
      });
      if (row.any((c) => c.isNotEmpty)) grid.add(row);
    }
    return grid;
  }
}

class _Span {
  final int start;
  final int end;
  _Span(this.start, this.end);
}

/// Reads little-endian values across a list of byte spans (an SST record and
/// its CONTINUE records), tracking span boundaries for string re-flag bytes.
class _SpanReader {
  final Uint8List b;
  final List<_Span> spans;
  int spanIdx = 0;
  int off; // absolute offset within the current span
  _SpanReader(this.b, this.spans) : off = spans.first.start;

  bool get done => spanIdx >= spans.length ||
      (spanIdx == spans.length - 1 && off >= spans.last.end);

  /// Advance past exhausted spans, then report whether the cursor sits at the
  /// very start of a continuation span (where a fresh string-flags byte lives).
  bool enteringNewSpan() {
    _advanceSpan();
    return spanIdx > 0 && spanIdx < spans.length && off == spans[spanIdx].start;
  }

  void _advanceSpan() {
    while (spanIdx < spans.length && off >= spans[spanIdx].end) {
      spanIdx++;
      if (spanIdx < spans.length) off = spans[spanIdx].start;
    }
  }

  int u8() {
    _advanceSpan();
    if (done) return 0;
    return b[off++];
  }

  int u16() => u8() | (u8() << 8);
  int u32() => u16() | (u16() << 16);

  /// A UTF-16 code unit never straddles a record boundary in practice; read
  /// both bytes from the current span (falling back to crossing if needed).
  int u16NoCross() {
    _advanceSpan();
    if (done) return 0;
    if (off + 2 <= spans[spanIdx].end) {
      final v = b[off] | (b[off + 1] << 8);
      off += 2;
      return v;
    }
    return u16();
  }

  void skip(int n) {
    for (var i = 0; i < n; i++) {
      u8();
    }
  }
}
