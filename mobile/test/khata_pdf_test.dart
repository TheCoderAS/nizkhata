import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:nizkhata/services/khata_pdf.dart';

void main() {
  final entries = [
    KhataEntry(DateTime(2025, 4, 20), 'Rent April', 18000),
    KhataEntry(DateTime(2025, 4, 2), 'Grocery split', -450.50),
  ];
  final dues = [
    KhataDueLine('Rent May', DateTime(2025, 5, 5), 18000, 'receivable'),
  ];

  test('khata PDF renders with position, dues and ledger', () {
    final bytes = buildKhataPdf(
      workspaceName: 'Family',
      contactName: 'Rahul Sharma',
      net: 17549.50,
      entries: entries,
      openDues: dues,
      currency: 'INR',
    );
    expect(bytes.length, greaterThan(1000));
    // Round-trip through the PDF text extractor to prove real content.
    final doc = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(doc).extractText();
    doc.dispose();
    expect(text, contains('Rahul Sharma'));
    expect(text, contains('Rent May'));
    expect(text, contains('Rent April'));
    expect(text, contains('nizkhata.web.app'));
  });

  test('many entries paginate without errors', () {
    final big = [
      for (var i = 0; i < 120; i++)
        KhataEntry(DateTime(2025, 1, 1).add(Duration(days: i)), 'Entry number $i', (i % 2 == 0 ? 1 : -1) * (100.0 + i)),
    ];
    final bytes = buildKhataPdf(
      workspaceName: 'Biz',
      contactName: 'Acme',
      net: -1200,
      entries: big,
      openDues: const [],
      currency: 'INR',
    );
    final doc = PdfDocument(inputBytes: bytes);
    expect(doc.pages.count, greaterThan(1));
    final text = PdfTextExtractor(doc).extractText();
    doc.dispose();
    expect(text, contains('Entry number 119'));
  });

  test('khata text summary reads correctly for both directions', () {
    final receive = buildKhataText(
        contactName: 'Rahul', net: 500, entries: entries, openDues: dues, currency: 'INR');
    expect(receive, contains('To receive'));
    expect(receive, contains('Rent May'));
    final pay = buildKhataText(
        contactName: 'Rahul', net: -500, entries: entries, openDues: const [], currency: 'INR');
    expect(pay, contains('To pay'));
    final even = buildKhataText(
        contactName: 'Rahul', net: 0, entries: const [], openDues: const [], currency: 'INR');
    expect(even, contains('All settled'));
  });

  test('due reminder text: overdue vs upcoming wording', () {
    final overdue = buildDueReminderText(
        contactName: 'Rahul',
        dueTitle: 'Rent April',
        remaining: 18000,
        dueDate: DateTime(2020, 4, 5),
        currency: 'INR');
    expect(overdue, contains('was due on'));
    final upcoming = buildDueReminderText(
        contactName: 'Rahul',
        dueTitle: 'Rent later',
        remaining: 18000,
        dueDate: DateTime.now().add(const Duration(days: 10)),
        currency: 'INR');
    expect(upcoming, contains('is due by'));
  });
}
