import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:nizkhata/services/khata_pdf.dart';

void main() {
  // A realistic mix: a lend (moves the position), a tagged-only expense
  // (does NOT move it), and a partial repayment. Σ deltas = 17,549.50 = net.
  final entries = [
    KhataEntry(DateTime(2025, 4, 20), 'Part repayment received', 450.50, positionDelta: -450.50),
    KhataEntry(DateTime(2025, 4, 2), 'Grocery split', -220, positionDelta: 0),
    KhataEntry(DateTime(2025, 4, 1), 'Rent April lent', -18000, positionDelta: 18000),
  ];
  final dues = [
    KhataDueLine('Rent May', DateTime(2025, 5, 5), 18000, 'receivable'),
  ];

  test('khata PDF renders with position, dues, ledger and running balance', () {
    // Real logo asset — proves the white header + PdfBitmap path end-to-end.
    final logo = File('assets/icon.png').readAsBytesSync();
    final bytes = buildKhataPdf(
      workspaceName: 'Family',
      contactName: 'Rahul Sharma',
      net: 17549.50,
      entries: entries,
      openDues: dues,
      currency: 'INR',
      logoPng: logo,
    );
    expect(bytes.length, greaterThan(1000));
    // Round-trip through the PDF text extractor to prove real content.
    final doc = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(doc).extractText();
    doc.dispose();
    expect(text, contains('NizKhata')); // header wordmark at positive y
    expect(text, contains('Rahul Sharma'));
    expect(text, contains('Rent May'));
    expect(text, contains('Rent April'));
    expect(text, contains('Balance')); // running-balance column header
    // The ledger reconciles with the banner: lend 18,000, tagged-only
    // expense (no movement), repayment 450.50 ⇒ closing balance = net.
    expect(text, contains('17,549.50')); // newest row balance == banner net
    expect('17,549.50'.allMatches(text).length, 2,
        reason: 'net appears in the banner AND as the closing ledger balance');
    expect('18,000.00'.allMatches(text).length, greaterThanOrEqualTo(3),
        reason: 'lend amount, its balance, and the unchanged balance on the '
            'tagged-only row');
    expect(text, contains('nizkhata.web.app'));
  });

  test('many entries paginate without errors', () {
    final big = [
      for (var i = 0; i < 120; i++)
        KhataEntry(DateTime(2025, 1, 1).add(Duration(days: i)), 'Entry number $i',
            (i % 2 == 0 ? 1 : -1) * (100.0 + i),
            positionDelta: (i % 2 == 0 ? 1 : -1) * (100.0 + i)),
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
    final receive =
        buildKhataText(contactName: 'Rahul', net: 500, entries: entries, openDues: dues, currency: 'INR');
    expect(receive, contains('Closing balance receivable'));
    expect(receive, contains('Rent May'));
    expect(receive, contains('https://nizkhata.web.app'));
    expect(receive, isNot(contains('—'))); // humanized: no em-dashes
    final pay = buildKhataText(
        contactName: 'Rahul', net: -500, entries: entries, openDues: const [], currency: 'INR');
    expect(pay, contains('Closing balance payable'));
    final even =
        buildKhataText(contactName: 'Rahul', net: 0, entries: const [], openDues: const [], currency: 'INR');
    expect(even, contains('The account is settled'));
  });

  test('due reminder text adapts to direction and timing', () {
    final askOverdue = buildDueReminderText(
        contactName: 'Rahul',
        dueTitle: 'Rent April',
        remaining: 18000,
        dueDate: DateTime(2020, 4, 5),
        currency: 'INR',
        direction: 'receivable');
    // The figures stand on their own lines so they can be checked at a glance.
    expect(askOverdue, contains('*Payment reminder: Rent April*'));
    expect(askOverdue, contains('Amount: '));
    expect(askOverdue, contains('Due date: 05 Apr 2020 (overdue)'));
    expect(askOverdue, contains('Kindly arrange the payment at the earliest'));
    expect(askOverdue, contains('https://nizkhata.web.app'));
    expect(askOverdue, isNot(contains('—'))); // humanized: no em-dashes

    final askUpcoming = buildDueReminderText(
        contactName: 'Rahul',
        dueTitle: 'Rent later',
        remaining: 18000,
        dueDate: DateTime.now().add(const Duration(days: 10)),
        currency: 'INR',
        direction: 'receivable');
    expect(askUpcoming, contains('on or before the due date'));
    expect(askUpcoming, isNot(contains('(overdue)')));

    // Payable: an advice about money going OUT, never a request for payment.
    final oweUpcoming = buildDueReminderText(
        contactName: 'Sonali',
        dueTitle: 'Partner RD - Aug',
        remaining: 5000,
        dueDate: DateTime.now().add(const Duration(days: 3)),
        currency: 'INR',
        direction: 'payable');
    expect(oweUpcoming, contains('*Payment advice: Partner RD - Aug*'));
    expect(oweUpcoming, contains('will be released on or before the due date'));
    // Nothing in a payable notice may read as asking them for money.
    expect(oweUpcoming, isNot(contains('Kindly arrange')));
    expect(oweUpcoming, isNot(contains('Payment reminder')));

    final oweOverdue = buildDueReminderText(
        contactName: 'Sonali',
        dueTitle: 'Partner RD - Jul',
        remaining: 5000,
        dueDate: DateTime(2020, 7, 31),
        currency: 'INR',
        direction: 'payable');
    expect(oweOverdue, contains('pending at my end'));
    expect(oweOverdue, contains('Apologies for the delay'));
    expect(oweOverdue, isNot(contains('Kindly arrange')));
  });
}
