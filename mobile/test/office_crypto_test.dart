import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/services/office_crypto.dart';
import 'package:nizkhata/services/statement_parser.dart';

// Fixtures: statement_plain.xlsx and its agile-encrypted twin
// statement_agile.xlsx (password "s3cret"), produced with openpyxl +
// msoffcrypto-tool (real ECMA-376 agile encryption, AES-256-CBC / SHA-512).
void main() {
  test('detects an encrypted OOXML container', () {
    final enc = File('test/fixtures/statement_agile.xlsx').readAsBytesSync();
    final plain = File('test/fixtures/statement_plain.xlsx').readAsBytesSync();
    expect(isEncryptedOfficeContainer(enc), true);
    expect(isEncryptedOfficeContainer(plain), false); // plain xlsx is a PK zip
  });

  test('agile: correct password decrypts to a valid xlsx zip', () {
    final enc = File('test/fixtures/statement_agile.xlsx').readAsBytesSync();
    final out = decryptOfficeDocument(enc, 's3cret');
    // The decrypted bytes are a plain .xlsx (PK zip).
    expect(out.sublist(0, 2), [0x50, 0x4b]);
    // And they parse through the normal statement pipeline.
    final grid = parseStatement(out, 'decrypted.xlsx');
    expect(grid.kind, StatementKind.excel);
    expect(grid.header, ['Date', 'Narration', 'Debit', 'Credit']);
  });

  test('agile: wrong password is rejected', () {
    final enc = File('test/fixtures/statement_agile.xlsx').readAsBytesSync();
    expect(() => decryptOfficeDocument(enc, 'nope'), throwsA(isA<WrongOfficePassword>()));
  });

  test('parseStatement: encrypted xlsx prompts, retries, then opens', () {
    final enc =
        Uint8List.fromList(File('test/fixtures/statement_agile.xlsx').readAsBytesSync());
    // No password → password required (not wrong).
    expect(
      () => parseStatement(enc, 'statement.xlsx'),
      throwsA(isA<StatementPasswordRequired>()
          .having((e) => e.wrongPassword, 'wrongPassword', false)),
    );
    // Wrong password → wrong-password signal.
    expect(
      () => parseStatement(enc, 'statement.xlsx', password: 'nope'),
      throwsA(isA<StatementPasswordRequired>()
          .having((e) => e.wrongPassword, 'wrongPassword', true)),
    );
    // Right password → real grid with parseable rows.
    final grid = parseStatement(enc, 'statement.xlsx', password: 's3cret');
    final rows = buildImportRows(grid, suggestMapping(grid.header), DateOrder.dmy);
    expect(rows.length, 3);
    expect(rows[0].amount, -450.0);
    expect(rows[1].amount, 50000.0);
  });
}
