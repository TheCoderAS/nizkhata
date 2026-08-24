// On-device decryption of password-protected Office documents (the modern
// OOXML container: an OLE2/CFB file holding EncryptionInfo + EncryptedPackage).
// Implements ECMA-376 "agile" (AES-CBC, iterated hash) and "standard"
// (AES-ECB, SHA-1) encryption per MS-OFFCRYPTO. Given the right password this
// returns the decrypted .xlsx (a plain zip) which the normal reader then opens.
//
// All local: the password and derived keys live only in memory.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/ecb.dart';

import 'cfb.dart';

class WrongOfficePassword implements Exception {}

class UnsupportedOfficeEncryption implements Exception {
  final String message;
  UnsupportedOfficeEncryption(this.message);
  @override
  String toString() => message;
}

/// True if [bytes] is an encrypted-OOXML CFB container (has EncryptedPackage).
bool isEncryptedOfficeContainer(Uint8List bytes) {
  try {
    return CfbReader(bytes).hasStream('EncryptedPackage');
  } catch (_) {
    return false;
  }
}

/// Decrypt an encrypted-OOXML container to its inner .xlsx/.docx zip bytes.
/// Throws [WrongOfficePassword] or [UnsupportedOfficeEncryption].
Uint8List decryptOfficeDocument(Uint8List bytes, String password) {
  final CfbReader cfb;
  try {
    cfb = CfbReader(bytes);
  } on CfbError catch (e) {
    throw UnsupportedOfficeEncryption(e.message);
  }
  final info = cfb.readStream('EncryptionInfo');
  final package = cfb.readStream('EncryptedPackage');
  if (info == null || package == null) {
    throw UnsupportedOfficeEncryption('Not an encrypted Office document.');
  }
  final major = ByteData.sublistView(info).getUint16(0, Endian.little);
  final minor = ByteData.sublistView(info).getUint16(2, Endian.little);

  if (minor == 4 && major == 4) {
    return _Agile(info, package, password).decrypt();
  }
  if (minor == 2 && (major == 4 || major == 3) || (major == 2 && minor == 2)) {
    return _Standard(info, package, password).decrypt();
  }
  throw UnsupportedOfficeEncryption(
      'Unsupported Office encryption version $major.$minor.');
}

// ---- hashing helpers -------------------------------------------------------

c.Hash _hashFor(String algo) {
  switch (algo.toUpperCase().replaceAll('-', '')) {
    case 'SHA1':
      return c.sha1;
    case 'SHA256':
      return c.sha256;
    case 'SHA384':
      return c.sha384;
    case 'SHA512':
      return c.sha512;
    default:
      throw UnsupportedOfficeEncryption('Unsupported hash algorithm "$algo".');
  }
}

Uint8List _hash(c.Hash h, List<int> data) =>
    Uint8List.fromList(h.convert(data).bytes);

Uint8List _concat(List<int> a, List<int> b) =>
    Uint8List.fromList([...a, ...b]);

/// UTF-16LE bytes of the password.
Uint8List _pwBytes(String password) {
  final out = BytesBuilder();
  for (final u in password.codeUnits) {
    out.addByte(u & 0xFF);
    out.addByte((u >> 8) & 0xFF);
  }
  return out.toBytes();
}

Uint8List _le32(int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  return b.buffer.asUint8List();
}

/// Fit [data] to [size] bytes: truncate, or pad with 0x36 (per MS-OFFCRYPTO).
Uint8List _fit(Uint8List data, int size) {
  if (data.length == size) return data;
  if (data.length > size) return Uint8List.sublistView(data, 0, size);
  final out = Uint8List(size)..fillRange(0, size, 0x36);
  out.setRange(0, data.length, data);
  return out;
}

// ---- AES -------------------------------------------------------------------

Uint8List _aesCbcDecrypt(Uint8List key, Uint8List iv, Uint8List data) {
  final cipher = CBCBlockCipher(AESEngine())
    ..init(false, ParametersWithIV(KeyParameter(key), iv));
  return _runBlocks(cipher, data);
}

Uint8List _aesEcbDecrypt(Uint8List key, Uint8List data) {
  final cipher = ECBBlockCipher(AESEngine())..init(false, KeyParameter(key));
  return _runBlocks(cipher, data);
}

/// Process [data] block-by-block (input is expected to be a whole number of
/// 16-byte blocks; a short trailing remainder is passed through untouched).
Uint8List _runBlocks(BlockCipher cipher, Uint8List data) {
  final out = Uint8List(data.length);
  final bs = cipher.blockSize;
  var off = 0;
  while (off + bs <= data.length) {
    cipher.processBlock(data, off, out, off);
    off += bs;
  }
  if (off < data.length) out.setRange(off, data.length, data, off);
  return out;
}

// ---- agile (AES-CBC, iterated hash) ----------------------------------------

const _blkVerifierInput = [0xfe, 0xa7, 0xd2, 0x76, 0x3b, 0x4b, 0x9e, 0x79];
const _blkVerifierValue = [0xd7, 0xaa, 0x0f, 0x6d, 0x30, 0x61, 0x34, 0x4e];
const _blkKeyValue = [0x14, 0x6e, 0x0b, 0xe7, 0xab, 0xac, 0xd0, 0xd6];

class _Agile {
  final Uint8List info;
  final Uint8List package;
  final String password;
  _Agile(this.info, this.package, this.password);

  Uint8List decrypt() {
    final xml = utf8.decode(Uint8List.sublistView(info, 8), allowMalformed: true);
    final keyData = _element(xml, 'keyData');
    final encKey = _passwordKeyEncryptor(xml);

    final kdHash = _hashFor(_attr(keyData, 'hashAlgorithm'));
    final kdSalt = _b64(_attr(keyData, 'saltValue'));
    final kdBlockSize = int.parse(_attr(keyData, 'blockSize'));

    final ekHash = _hashFor(_attr(encKey, 'hashAlgorithm'));
    final ekSalt = _b64(_attr(encKey, 'saltValue'));
    final spinCount = int.parse(_attr(encKey, 'spinCount'));
    final keyBytes = int.parse(_attr(encKey, 'keyBits')) ~/ 8;
    final hashSize = int.parse(_attr(encKey, 'hashSize'));

    // Iterated password hash: H_n = hash(LE32(n) + H_{n-1}).
    var h = _hash(ekHash, _concat(ekSalt, _pwBytes(password)));
    for (var i = 0; i < spinCount; i++) {
      h = _hash(ekHash, _concat(_le32(i), h));
    }

    Uint8List deriveKey(List<int> blockKey) =>
        _fit(_hash(ekHash, _concat(h, blockKey)), keyBytes);

    // Verify the password before trusting anything else.
    final verifier = _aesCbcDecrypt(
        deriveKey(_blkVerifierInput), ekSalt, _b64(_attr(encKey, 'encryptedVerifierHashInput')));
    final expected = _aesCbcDecrypt(
        deriveKey(_blkVerifierValue), ekSalt, _b64(_attr(encKey, 'encryptedVerifierHashValue')));
    final actual = _hash(ekHash, verifier);
    if (!_bytesEqual(actual, expected, hashSize)) throw WrongOfficePassword();

    // Recover the package secret key.
    final secretKey = _fit(
        _aesCbcDecrypt(
            deriveKey(_blkKeyValue), ekSalt, _b64(_attr(encKey, 'encryptedKeyValue'))),
        keyBytes);

    // Decrypt the package in 4096-byte segments, each with IV = hash(salt+LE32(seg)).
    final totalSize = ByteData.sublistView(package, 0, 8).getUint64(0, Endian.little);
    final cipherData = Uint8List.sublistView(package, 8);
    final out = BytesBuilder();
    const segLen = 4096;
    var seg = 0;
    for (var off = 0; off < cipherData.length; off += segLen) {
      final end = (off + segLen > cipherData.length) ? cipherData.length : off + segLen;
      final chunk = Uint8List.sublistView(cipherData, off, end);
      final iv = _fit(_hash(kdHash, _concat(kdSalt, _le32(seg))), kdBlockSize);
      out.add(_aesCbcDecrypt(secretKey, iv, chunk));
      seg++;
    }
    final all = out.toBytes();
    return totalSize <= all.length ? Uint8List.sublistView(all, 0, totalSize) : all;
  }

  /// The <keyEncryptor> whose child is the password (p:encryptedKey) element.
  String _passwordKeyEncryptor(String xml) {
    final m = RegExp(r'<[a-z]?:?encryptedKey\b[^>]*/?>', caseSensitive: false).firstMatch(xml);
    if (m == null) {
      throw UnsupportedOfficeEncryption('No password key in this document '
          '(it may use certificate-based protection).');
    }
    return m.group(0)!;
  }
}

// ---- standard (AES-ECB, SHA-1) ---------------------------------------------

class _Standard {
  final Uint8List info;
  final Uint8List package;
  final String password;
  _Standard(this.info, this.package, this.password);

  Uint8List decrypt() {
    // Header: version(4) + flags(4) + headerSize(4) + EncryptionHeader + EncryptionVerifier.
    final d = ByteData.sublistView(info);
    final headerSize = d.getUint32(8, Endian.little);
    const headerStart = 12;
    // EncryptionHeader fields we need: KeySize at offset +32 within the header.
    final keyBits = d.getUint32(headerStart + 32, Endian.little);
    final keyBytes = (keyBits == 0 ? 128 : keyBits) ~/ 8;

    final verifierStart = headerStart + headerSize;
    final saltSize = d.getUint32(verifierStart, Endian.little);
    final salt = Uint8List.sublistView(info, verifierStart + 4, verifierStart + 4 + saltSize);
    final encVerifier =
        Uint8List.sublistView(info, verifierStart + 4 + saltSize, verifierStart + 4 + saltSize + 16);
    final vhStart = verifierStart + 4 + saltSize + 16;
    final verifierHashSize = d.getUint32(vhStart, Endian.little);
    final encVerifierHash = Uint8List.sublistView(info, vhStart + 4, vhStart + 4 + 32);

    // Key derivation (SHA-1, 50000 iterations, block 0).
    var h = _hash(c.sha1, _concat(salt, _pwBytes(password)));
    for (var i = 0; i < 50000; i++) {
      h = _hash(c.sha1, _concat(_le32(i), h));
    }
    h = _hash(c.sha1, _concat(h, _le32(0)));
    final key = _deriveStandardKey(h, keyBytes);

    // Verify.
    final verifier = _aesEcbDecrypt(key, encVerifier);
    final vHash = _aesEcbDecrypt(key, encVerifierHash);
    if (!_bytesEqual(_hash(c.sha1, verifier), vHash, verifierHashSize == 0 ? 20 : verifierHashSize)) {
      throw WrongOfficePassword();
    }

    // Decrypt the package (ECB, no IV); first 8 bytes are the plaintext size.
    final totalSize = ByteData.sublistView(package, 0, 8).getUint64(0, Endian.little);
    final plain = _aesEcbDecrypt(key, Uint8List.sublistView(package, 8));
    return totalSize <= plain.length ? Uint8List.sublistView(plain, 0, totalSize) : plain;
  }

  /// Standard key block: X1=H(0x36⊕Hfinal), X2=H(0x5C⊕Hfinal), key=(X1‖X2)[:n].
  Uint8List _deriveStandardKey(Uint8List hfinal, int keyBytes) {
    Uint8List pad(int b) {
      final buf = Uint8List(64)..fillRange(0, 64, b);
      for (var i = 0; i < hfinal.length && i < 64; i++) {
        buf[i] = b ^ hfinal[i];
      }
      return buf;
    }

    final x1 = _hash(c.sha1, pad(0x36));
    final x2 = _hash(c.sha1, pad(0x5c));
    return _fit(_concat(x1, x2), keyBytes);
  }
}

// ---- tiny XML/attr helpers (the descriptor is a fixed, simple shape) --------

String _element(String xml, String name) {
  final m = RegExp('<[a-z]?:?$name\\b[^>]*/?>', caseSensitive: false).firstMatch(xml);
  if (m == null) throw UnsupportedOfficeEncryption('Malformed encryption descriptor.');
  return m.group(0)!;
}

String _attr(String element, String name) {
  final m = RegExp('$name\\s*=\\s*"([^"]*)"').firstMatch(element);
  if (m == null) {
    throw UnsupportedOfficeEncryption('Missing "$name" in encryption descriptor.');
  }
  return m.group(1)!;
}

Uint8List _b64(String s) => base64.decode(s.trim());

bool _bytesEqual(Uint8List a, Uint8List b, int len) {
  if (a.length < len || b.length < len) return false;
  var diff = 0;
  for (var i = 0; i < len; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
