// Formatting helpers — ports of src/lib/utils.ts (formatMoney/formatDate/
// initials/avatarColor) so numbers and dates read identically to the web app.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'currency.dart';

/// Which locale dates are written in. Set once at startup from the phone
/// (see main.dart); it defaults to en_IN so tests, and anything that runs
/// before startup finishes, read exactly as the app always has.
class AppLocale {
  AppLocale._();
  static String date = 'en_IN';
}

/// The English date locale closest to the phone's. English because every
/// other word in the app is: a date in Devanagari between two English words
/// reads worse than either. So an English phone keeps its own variant
/// (en_US, en_GB, en_AU), any other phone gets English for its country when
/// intl has one, and failing both, en_IN — the app's long-standing format.
String resolveDateLocale(Locale device, {bool Function(String)? exists}) {
  final has = exists ?? DateFormat.localeExists;
  final country = device.countryCode;
  final candidates = [
    if (device.languageCode == 'en' && country != null) 'en_$country',
    if (country != null) 'en_$country',
  ];
  for (final c in candidates) {
    if (has(c)) return c;
  }
  return 'en_IN';
}

/// Format as workspace currency (defaults INR / en-IN). Accounting sign: a
/// negative renders in parentheses, e.g. -1000 -> "(₹1,000.00)". A true zero
/// (|amount| < 0.005) renders as an em dash — matching the web.
///
/// The currency decides everything about how the figure is written: symbol,
/// decimal places, and whether digits group in lakhs or in thousands. [locale]
/// overrides only the grouping, and nothing in the app needs to pass it.
String formatMoney(num amount, [String currency = 'INR', String? locale]) {
  final spec = currencySpec(currency);
  if (amount.abs() < _zeroBelow(spec)) return '—';
  final fmt = NumberFormat.currency(
    locale: locale ?? spec.numberLocale,
    symbol: spec.symbol,
    decimalDigits: spec.decimals,
  );
  if (amount < 0) {
    return '(${fmt.format(amount.abs())})';
  }
  return fmt.format(amount);
}

/// Compact currency for tight spaces (stat cards). South Asian currencies use
/// their own short scale — ₹43.5K, ₹2.5L, ₹1.2Cr — and everyone else the
/// international one — \$43.5K, \$2.5M, \$1.2B. Keeps the accounting sign
/// (negatives parenthesised) and em-dash zero. Values under 1,000 render in
/// full so small numbers stay exact.
String formatMoneyCompact(num amount, [String currency = 'INR']) {
  final spec = currencySpec(currency);
  if (amount.abs() < _zeroBelow(spec)) return '—';
  final neg = amount < 0;
  final v = amount.abs();
  String body;
  if (v < 1000) {
    // Whole units when exact, else the currency's own decimal places.
    body = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(spec.decimals);
  } else if (spec.grouping == DigitGrouping.southAsian) {
    if (v < 100000) {
      body = '${_trim(v / 1000)}K';
    } else if (v < 10000000) {
      body = '${_trim(v / 100000)}L';
    } else {
      body = '${_trim(v / 10000000)}Cr';
    }
  } else {
    if (v < 1000000) {
      body = '${_trim(v / 1000)}K';
    } else if (v < 1000000000) {
      body = '${_trim(v / 1000000)}M';
    } else {
      body = '${_trim(v / 1000000000)}B';
    }
  }
  final s = '${spec.symbol}$body';
  return neg ? '($s)' : s;
}

/// The symbol to put in front of an amount field, e.g. `₹`, `\$`, `AED`.
/// Trailing space trimmed: an input's prefix already sits apart from the text.
String currencySymbol(String currency) => currencySpec(currency).symbol.trimRight();

/// Below half a minor unit a figure is nothing. For a two-decimal currency
/// that is the long-standing 0.005; for the yen it is half a yen.
double _zeroBelow(CurrencySpec spec) => 0.5 / _pow10(spec.decimals);

double _pow10(int n) {
  var v = 1.0;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

/// One decimal, but drop a trailing ".0" so "90.0" -> "90".
String _trim(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}


/// Balance label for an account row.
///
/// Every account reads the same way, in the oldest notation there is: money you
/// are down shows in parentheses. A drawn credit card is "(₹1,000.00)", an
/// overdrawn bank account is "(₹1,000.00)", and no word is needed to say which
/// direction either one runs.
///
/// The account type is still taken so callers do not all have to change if a
/// type ever needs its own treatment again.
String accountBalanceLabel(String accountType, num balance, [String currency = 'INR']) =>
    formatMoney(balance, currency);

/// Short readable date in the reader's own convention: "9 Aug 2026" in India
/// and Britain, "Aug 9, 2026" in the US. Follows the phone, not the workspace:
/// how a date is written is a personal preference, not something the books
/// have to agree on.
String formatDate(DateTime date, [String? locale]) {
  return DateFormat.yMMMd(locale ?? AppLocale.date).format(date);
}

/// Up-to-2-letter initials from a name or email.
String initialsOf(String nameOrEmail) {
  final parts = nameOrEmail.trim().split(RegExp(r'[\s@.]+')).where((p) => p.isNotEmpty).toList();
  final a = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0] : '?';
  final b = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
  return (a + b).toUpperCase();
}

/// Deterministic gradient avatar colours from a seed (stable per name).
({Color from, Color to}) avatarGradient(String seed) {
  var hash = 0;
  for (var i = 0; i < seed.length; i++) {
    hash = (hash * 31 + seed.codeUnitAt(i)) & 0x7fffffff;
  }
  final hue = hash % 360;
  return (
    from: HSLColor.fromAHSL(1, hue.toDouble(), 0.70, 0.55).toColor(),
    to: HSLColor.fromAHSL(1, ((hue + 40) % 360).toDouble(), 0.72, 0.48).toColor(),
  );
}

/// A day of the month as people say it: 1st, 2nd, 3rd, 21st, 31st.
String ordinalDay(int day) {
  // 11th, 12th and 13th break the pattern the last digit would suggest.
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}
