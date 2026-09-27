// How a figure is written, per currency. The currency decides the symbol, the
// decimal places and the digit grouping; nothing else should have to.

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nizkhata/core/currency.dart';
import 'package:nizkhata/core/format.dart';
import 'package:nizkhata/data/derive.dart';

void main() {
  setUpAll(() async => initializeDateFormatting());
  // roundMoney reads a process-wide context; never let one test's currency
  // leak into the next.
  tearDown(() => MoneyContext.currency = 'INR');

  group('INR is exactly what it always was', () {
    test('lakh grouping, rupee symbol, two decimals', () {
      expect(formatMoney(1234567.5, 'INR'), '₹12,34,567.50');
      expect(formatMoney(-1000, 'INR'), '(₹1,000.00)');
      expect(formatMoney(0, 'INR'), '—');
    });

    test('compact in thousands, lakhs and crores', () {
      expect(formatMoneyCompact(43500, 'INR'), '₹43.5K');
      expect(formatMoneyCompact(250000, 'INR'), '₹2.5L');
      expect(formatMoneyCompact(12000000, 'INR'), '₹1.2Cr');
    });
  });

  group('international currencies group in thousands', () {
    test('a million dollars is 1,000,000 — not 10,00,000', () {
      expect(formatMoney(1000000, 'USD'), '\$1,000,000.00');
      expect(formatMoney(1234567.5, 'EUR'), '€1,234,567.50');
      expect(formatMoney(-2500, 'GBP'), '(£2,500.00)');
    });

    test('compact in thousands, millions and billions — never L or Cr', () {
      expect(formatMoneyCompact(43500, 'USD'), '\$43.5K');
      expect(formatMoneyCompact(250000, 'USD'), '\$250K');
      expect(formatMoneyCompact(2500000, 'USD'), '\$2.5M');
      expect(formatMoneyCompact(1200000000, 'USD'), '\$1.2B');
    });

    test('other South Asian rupees keep lakh grouping', () {
      expect(formatMoney(1234567, 'PKR'), 'Rs 12,34,567.00');
      expect(formatMoneyCompact(250000, 'BDT'), '৳2.5L');
    });
  });

  group('decimal places follow the currency', () {
    test('the yen has none', () {
      expect(formatMoney(1500, 'JPY'), '¥1,500');
      expect(formatMoneyCompact(999, 'JPY'), '¥999');
    });

    test('the Kuwaiti dinar has three', () {
      expect(formatMoney(12.345, 'KWD'), 'KWD 12.345');
    });

    test('half a minor unit is the edge of nothing', () {
      // Half a yen is nothing; half a fil is nothing; half a paisa is nothing.
      expect(formatMoney(0.4, 'JPY'), '—');
      expect(formatMoney(0.6, 'JPY'), '¥1');
      expect(formatMoney(0.0004, 'KWD'), '—');
      expect(formatMoney(0.004, 'INR'), '—');
    });
  });

  group('rounding follows the active workspace', () {
    test('INR, the default, rounds to paise as it always has', () {
      expect(roundMoney(33.3333), 33.33);
      expect(roundMoney(0.1 + 0.2), 0.3);
    });

    test('a yen workspace rounds to whole yen', () {
      MoneyContext.currency = 'JPY';
      expect(roundMoney(33.3333), 33);
      expect(roundMoney(100 / 3 * 3), 100);
    });

    test('a dinar workspace keeps the third decimal a two-place round would lose', () {
      MoneyContext.currency = 'KWD';
      expect(roundMoney(1.2345), 1.235);
      expect(roundMoney(1.234), 1.234);
    });
  });

  group('an unknown code still formats sensibly', () {
    test('its own code as the symbol, two decimals, thousands', () {
      expect(formatMoney(1000000, 'XYZ'), 'XYZ 1,000,000.00');
      expect(currencySpec('xyz').code, 'XYZ');
    });
  });

  group('the amount-field prefix', () {
    test('is the bare symbol', () {
      expect(currencySymbol('INR'), '₹');
      expect(currencySymbol('USD'), '\$');
      expect(currencySymbol('AED'), 'AED');
    });
  });

  group('suggesting a currency from the phone', () {
    test('maps the country, and admits when it does not know', () {
      expect(currencyForCountry('IN'), 'INR');
      expect(currencyForCountry('us'), 'USD');
      expect(currencyForCountry('DE'), 'EUR');
      expect(currencyForCountry('AQ'), isNull);
      expect(currencyForCountry(null), isNull);
    });

    test('every catalogue currency a country maps to exists', () {
      for (final cc in ['IN', 'US', 'GB', 'AE', 'JP', 'KW', 'DE', 'PK', 'AU']) {
        final code = currencyForCountry(cc)!;
        expect(kCurrencies.any((c) => c.code == code), true, reason: '$cc -> $code');
      }
    });
  });

  group('dates follow the phone, in English', () {
    test('an English phone keeps its own variant', () {
      expect(resolveDateLocale(const Locale('en', 'US')), 'en_US');
      expect(resolveDateLocale(const Locale('en', 'GB')), 'en_GB');
    });

    test('a Hindi phone in India gets English for India, not Devanagari', () {
      expect(resolveDateLocale(const Locale('hi', 'IN')), 'en_IN');
    });

    test('with nothing to go on it falls back to the long-standing format', () {
      expect(resolveDateLocale(const Locale('xx')), 'en_IN');
      expect(resolveDateLocale(const Locale('fr', 'FR'), exists: (_) => false), 'en_IN');
    });

    test('US readers see month first; Indian readers see it as before', () {
      final d = DateTime(2026, 9, 20);
      expect(formatDate(d, 'en_US'), 'Sep 20, 2026');
      expect(formatDate(d, 'en_IN'), '20 Sept 2026');
      expect(formatDate(d), '20 Sept 2026'); // the default
    });
  });

  group('default financial year start', () {
    test('follows where the currency is used', () {
      expect(currencySpec('INR').defaultFyStartMonth, 4);
      expect(currencySpec('USD').defaultFyStartMonth, 1);
      expect(currencySpec('AUD').defaultFyStartMonth, 7);
    });
  });
}
