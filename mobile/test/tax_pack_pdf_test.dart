import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:nizkhata/services/tax_pack_pdf.dart';

void main() {
  test('tax pack renders heads, contacts and register across pages', () {
    final bytes = buildTaxPackPdf(
      workspaceName: 'Freelance',
      fy: '2025-26',
      currency: 'INR',
      totalTaxable: 1250000,
      totalTds: 125000,
      heads: [
        TaxHeadSummary('Professional services (194J)', 1000000, 100000, 24),
        TaxHeadSummary('Rent (194I)', 250000, 25000, 12),
      ],
      contacts: [
        TaxContactSummary('Acme Corp', 1000000, 100000),
        TaxContactSummary('Beta LLP', 250000, 25000),
      ],
      register: [
        for (var i = 0; i < 60; i++)
          TaxRegisterRow(DateTime(2025, 4, 1).add(Duration(days: i * 5)),
              'Invoice #${1000 + i} — consulting', 'Professional services (194J)', 41666.67, 4166.67),
      ],
    );
    expect(bytes.length, greaterThan(1500));
    final doc = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(doc).extractText();
    final pages = doc.pages.count;
    doc.dispose();
    expect(pages, greaterThan(1)); // 60-row register paginates
    expect(text, contains('NizKhata')); // white header wordmark, unclipped
    expect(text, contains('Tax pack for FY 2025-26'));
    expect(text, contains('194J'));
    expect(text, contains('Acme Corp'));
    expect(text, contains('Form 26AS'));
    expect(text, contains('Invoice #1059'));
    expect(text, contains('verify figures with your accountant'));
    expect(text, contains('Computer-generated statement'));
    expect(text, contains('Page 1 of')); // paged footer
    expect(text, contains('Total')); // emphasized totals row in by-head
  });

  test('empty sections are skipped without errors', () {
    final bytes = buildTaxPackPdf(
      workspaceName: 'W',
      fy: '2025-26',
      currency: 'INR',
      totalTaxable: 0,
      totalTds: 0,
      heads: const [],
      contacts: const [],
      register: const [],
    );
    final doc = PdfDocument(inputBytes: bytes);
    expect(doc.pages.count, 1);
    doc.dispose();
  });
}
