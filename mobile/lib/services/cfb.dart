// OLE2 / Compound File Binary reader — the container format wrapping legacy
// .xls workbooks and password-encrypted Office documents. Shared by the BIFF
// .xls decoder and the Office-crypto module.

import 'dart:typed_data';

const _endOfChain = 0xFFFFFFFE;
const _freeSect = 0xFFFFFFFF;

/// The file isn't a readable compound (OLE2) document.
class CfbError implements Exception {
  final String message;
  CfbError(this.message);
  @override
  String toString() => message;
}

class CfbReader {
  final Uint8List b;
  late final ByteData _d = ByteData.sublistView(b);
  late final int _sectorSize;
  late final int _miniSectorSize;
  late final int _miniCutoff;
  late final List<int> _fat;
  late final List<int> _miniFat;
  final List<CfbEntry> _entries = [];
  Uint8List _miniStream = Uint8List(0);

  CfbReader(this.b) {
    if (b.length < 512) throw CfbError('File too small to be a compound document.');
    _sectorSize = 1 << _u16(30);
    _miniSectorSize = 1 << _u16(32);
    _miniCutoff = _u32(56);
    if (_sectorSize < 128 || _sectorSize > 65536) {
      throw CfbError('Corrupt compound-document container.');
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
      _entries.add(CfbEntry(
        String.fromCharCodes(chars),
        d.getUint8(66),
        d.getUint32(116, Endian.little),
        d.getUint32(120, Endian.little),
      ));
    }
    for (final e in _entries) {
      if (e.type == 5) {
        _miniStream = _readChain(e.start, e.size);
        break;
      }
    }
  }

  /// Whether a stream (by exact case-insensitive name) exists.
  bool hasStream(String name) =>
      _entries.any((e) => e.type == 2 && e.name.toLowerCase() == name.toLowerCase());

  /// Read a stream's bytes by name, or null if absent.
  Uint8List? readStream(String name) {
    for (final e in _entries) {
      if (e.type != 2 || e.name.toLowerCase() != name.toLowerCase()) continue;
      return e.size < _miniCutoff ? _readMiniChain(e.start, e.size) : _readChain(e.start, e.size);
    }
    return null;
  }
}

class CfbEntry {
  final String name;
  final int type; // 1 storage, 2 stream, 5 root
  final int start;
  final int size;
  CfbEntry(this.name, this.type, this.start, this.size);
}
