// The ledger PDF and the messages sent from it, in any workspace currency:
// the currency's own symbol, decimals and grouping, never a rupee default.
// Also what the embedded Noto Sans lets the PDF draw, read back out of the
// finished document.

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:nizkhata/services/khata_pdf.dart';
import 'package:nizkhata/services/pdf_brand.dart';
import 'package:nizkhata/services/tax_pack_pdf.dart';

String _textOf(List<int> bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  final text = PdfTextExtractor(doc).extractText();
  doc.dispose();
  return text;
}

String _khata({
  required String currency,
  required double net,
  required List<KhataEntry> entries,
  List<KhataDueLine> dues = const [],
  String contactName = 'Dana Whitfield',
}) =>
    _textOf(buildKhataPdf(
      workspaceName: 'Home',
      contactName: contactName,
      net: net,
      entries: entries,
      openDues: dues,
      currency: currency,
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Through the app's own asset bundle, which also proves pubspec.yaml
    // registers the font.
    await PdfTypeface.load();
    expect(PdfTypeface.isLoaded, true, reason: 'the font assets must load');
  });

  group('a US dollar ledger', () {
    late String text;
    setUpAll(() {
      text = _khata(
        currency: 'USD',
        net: 1234567.5,
        entries: [
          KhataEntry(DateTime(2026, 3, 2), 'Paid back', 450.25, positionDelta: -450.25),
          KhataEntry(DateTime(2026, 3, 1), 'Loan', -1235017.75, positionDelta: 1235017.75),
        ],
        dues: [KhataDueLine('Car', DateTime(2026, 4, 1), 2500, 'receivable')],
      );
    });

    test('writes dollars, grouped in thousands, with cents', () {
      expect(text, contains('\$1,234,567.50'));
      expect(text, contains('\$1,235,017.75'));
      expect(text, contains('\$450.25'));
      expect(text, contains('\$2,500.00'));
    });

    test('has no trace of rupees or lakh grouping', () {
      expect(text, isNot(contains('Rs')));
      expect(text, isNot(contains('INR')));
      expect(text, isNot(contains('₹')));
      expect(text, isNot(contains('12,34,567')));
    });
  });

  group('a yen ledger', () {
    test('writes yen with no decimals', () {
      final text = _khata(
        currency: 'JPY',
        net: 1234567,
        entries: [KhataEntry(DateTime(2026, 3, 1), 'Loan', -1234567, positionDelta: 1234567)],
      );
      expect(text, contains('¥1,234,567'));
      expect(text, isNot(contains('¥1,234,567.00')));
      expect(text, isNot(contains('Rs')));
    });
  });

  group('a rupee ledger', () {
    test('draws the rupee sign itself and keeps lakh grouping', () {
      final text = _khata(
        currency: 'INR',
        net: 123456,
        entries: [KhataEntry(DateTime(2026, 3, 1), 'Loan', -123456, positionDelta: 123456)],
      );
      expect(text, contains('₹1,23,456.00'));
      expect(text, isNot(contains('Rs ')));
    });
  });

  group('names in other scripts', () {
    test('a Hindi name is drawn in Devanagari', () {
      final text = _khata(currency: 'INR', net: 100, entries: const [], contactName: 'राहुल शर्मा');
      expect(text, contains('राहुल'));
      expect(text, isNot(contains('?????')));
    });

    test('an Arabic name is drawn with its letters joined', () {
      final text = _khata(currency: 'AED', net: 100, entries: const [], contactName: 'أحمد');
      // The extractor hands back the joined (presentation) forms that were
      // drawn: initial alef-hamza, medial hah, medial meem, final dal. Loose
      // letters or '?' would mean the name was not shaped or not drawable.
      expect(text, contains('ﺃﺣﻤﺪ'));
      expect(text, contains('AED 100.00'));
    });

    test('a script the font lacks shows as ? rather than vanishing', () {
      expect(pdfSafe('王伟 Wang', embedded: true), '?? Wang');
    });

    test('the short-i sign is moved before its consonant, as shaping would', () {
      // अमित: अ म ि त is drawn as अ ि म त, which reads अमित on the page.
      expect(pdfSafe('अमित', embedded: true), 'अिमत');
    });
  });

  group('without the embedded font', () {
    tearDown(PdfTypeface.load);

    test('signs Helvetica cannot draw become ISO codes; the rest stay', () {
      PdfTypeface.unload();
      final entries = [KhataEntry(DateTime(2026, 3, 1), 'Loan', -1500, positionDelta: 1500)];
      expect(_khata(currency: 'INR', net: 1500, entries: entries), contains('INR 1,500.00'));
      PdfTypeface.unload();
      expect(_khata(currency: 'EUR', net: 1500, entries: entries), contains('EUR 1,500.00'));
      PdfTypeface.unload();
      expect(_khata(currency: 'USD', net: 1500, entries: entries), contains('\$1,500.00'));
    });
  });

  group('the tax pack', () {
    test('uses the workspace currency', () {
      final text = _textOf(buildTaxPackPdf(
        workspaceName: 'W',
        fy: '2026',
        currency: 'USD',
        totalTaxable: 125000,
        totalTds: 12500,
        heads: [TaxHeadSummary('Services', 125000, 12500, 3)],
        contacts: [TaxContactSummary('Acme', 125000, 12500)],
        register: [TaxRegisterRow(DateTime(2026, 1, 5), 'Invoice', 'Services', 125000, 12500)],
      ));
      expect(text, contains('\$125,000.00'));
      expect(text, contains('\$12,500.00'));
      expect(text, isNot(contains('Rs')));
    });
  });

  group('messages', () {
    test('the khata summary is in dollars', () {
      final t = buildKhataText(
        contactName: 'Dana',
        net: 1234.5,
        entries: [KhataEntry(DateTime(2026, 3, 1), 'Dinner', -80, positionDelta: 80)],
        openDues: [KhataDueLine('Tickets', DateTime(2026, 4, 1), 1154.5, 'receivable')],
        currency: 'USD',
      );
      expect(t, contains('Closing balance receivable: \$1,234.50'));
      expect(t, contains('Tickets: \$1,154.50'));
      expect(t, contains('-\$80.00'));
      expect(t, isNot(contains('Rs')));
      expect(t, isNot(contains('—')));
    });

    test('a reminder is in dollars, or yen without decimals', () {
      String reminder(String currency) => buildDueReminderText(
            contactName: 'Dana',
            dueTitle: 'Tickets',
            remaining: 18000,
            dueDate: DateTime(2020, 4, 5),
            currency: currency,
            direction: 'receivable',
          );
      expect(reminder('USD'), contains('Amount: \$18,000.00'));
      expect(reminder('JPY'), contains('Amount: ¥18,000\n'));
      expect(reminder('INR'), contains('Amount: ₹18,000.00'));
    });
  });
}
