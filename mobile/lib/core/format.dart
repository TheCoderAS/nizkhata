// Formatting helpers — ports of src/lib/utils.ts (formatMoney/formatDate/
// initials/avatarColor) so numbers and dates read identically to the web app.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Format as workspace currency (defaults INR / en-IN). Accounting sign: a
/// negative renders in parentheses, e.g. -1000 -> "(₹1,000.00)". A true zero
/// (|amount| < 0.005) renders as an em dash — matching the web.
String formatMoney(num amount, [String currency = 'INR', String locale = 'en_IN']) {
  if (amount.abs() < 0.005) return '—';
  final symbol = _currencySymbol(currency);
  final fmt = NumberFormat.currency(
    locale: locale,
    symbol: symbol,
    decimalDigits: 2,
  );
  if (amount < 0) {
    return '(${fmt.format(amount.abs())})';
  }
  return fmt.format(amount);
}

/// Compact currency for tight spaces (stat cards): Indian short scale —
/// ₹43.5K, ₹2.5L, ₹1.2Cr. Keeps the accounting sign (negatives parenthesised)
/// and em-dash zero. Values under 1,000 render in full so small numbers stay
/// exact. Two significant-ish digits keep everything on one line up to crores.
String formatMoneyCompact(num amount, [String currency = 'INR']) {
  if (amount.abs() < 0.005) return '—';
  final symbol = _currencySymbol(currency);
  final neg = amount < 0;
  final v = amount.abs();
  String body;
  if (v < 1000) {
    // Whole rupees when exact, else two decimals.
    body = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  } else if (v < 100000) {
    body = '${_trim(v / 1000)}K';
  } else if (v < 10000000) {
    body = '${_trim(v / 100000)}L';
  } else {
    body = '${_trim(v / 10000000)}Cr';
  }
  final s = '$symbol$body';
  return neg ? '($s)' : s;
}

/// One decimal, but drop a trailing ".0" so "90.0" -> "90".
String _trim(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

String _currencySymbol(String code) {
  switch (code) {
    case 'INR':
      return '₹';
    case 'USD':
      return '\$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    case 'AED':
      return 'AED ';
    case 'SGD':
      return 'S\$';
    case 'AUD':
      return 'A\$';
    case 'CAD':
      return 'C\$';
    default:
      return '$code ';
  }
}

/// Balance label for an account row. A credit card is a liability: a negative
/// balance is money you have drawn and not yet repaid, so it reads
/// "₹1,000.00 outstanding" rather than as a negative asset.
String accountBalanceLabel(String accountType, num balance, [String currency = 'INR']) {
  if (accountType == 'credit_card' && balance < 0) {
    return '${formatMoney(-balance, currency)} outstanding';
  }
  return formatMoney(balance, currency);
}

/// Short readable date, e.g. "9 Aug 2026".
String formatDate(DateTime date, [String locale = 'en_IN']) {
  return DateFormat('d MMM yyyy', locale).format(date);
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
