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
