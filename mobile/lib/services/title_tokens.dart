// Placeholders for recurring titles and notes.
//
// A recurring due's title has to do two jobs: name the series ("RD Payment")
// and stamp the occurrence ("Aug"). Copying it verbatim to the next instance
// carries last month's stamp forward, so the pattern carries tokens instead
// and each occurrence renders its own: "RD Payment - {MMM}".
//
// Rendering is deliberately forgiving in one direction only: an unknown token
// is left on screen exactly as typed. A typo should be visible, never silently
// swallowed.

import 'package:intl/intl.dart';

import '../core/format.dart';
import '../data/derive.dart';

/// One token, as offered by the form's insert chips and the "More" sheet.
class TokenSpec {
  final String token;
  final String label;
  final String description;
  const TokenSpec(this.token, this.label, this.description);
}

/// Everything the picker offers, in the order it is shown. The short list at
/// the top of a form is the first few; the rest live behind "More". Examples
/// are rendered live from the date being edited, so nothing here can drift.
const kTitleTokens = <TokenSpec>[
  TokenSpec('{MMM}', 'Month', 'Short month name'),
  TokenSpec('{YYYY}', 'Year', 'Four digit year'),
  TokenSpec('{DATE}', 'Date', 'The whole date'),
  TokenSpec('{FY}', 'FY', "Your workspace's financial year"),
  TokenSpec('{#}', 'Number', 'Which occurrence this is: 1, 2, 3…'),
  TokenSpec('{MMMM}', 'Month, full', 'Full month name'),
  TokenSpec('{MM}', 'Month, 2 digit', 'Month as a number'),
  TokenSpec('{YY}', 'Year, 2 digit', 'Last two digits of the year'),
  TokenSpec('{D}', 'Day', 'Day of the month'),
  TokenSpec('{DD}', 'Day, 2 digit', 'Day, zero padded'),
  TokenSpec('{Q}', 'Quarter', 'Calendar quarter'),
];

/// How many chips fit before "More" — the rest are still insertable there.
const kPrimaryTokenCount = 5;

final _tokenPattern = RegExp(r'\{\{|\{([A-Za-z#]+)([+-]\d+)?\}');

/// True when [text] carries at least one token this renderer understands.
bool hasTokens(String? text) {
  if (text == null || text.isEmpty) return false;
  for (final m in _tokenPattern.allMatches(text)) {
    final name = m.group(1);
    if (name != null && _isKnown(name)) return true;
  }
  return false;
}

bool _isKnown(String name) => switch (name.toUpperCase()) {
      'MMM' || 'MMMM' || 'MM' || 'YYYY' || 'YY' || 'D' || 'DD' || 'DATE' || 'Q' || 'FY' || '#' => true,
      _ => false,
    };

/// Render [pattern] for an occurrence dated [date].
///
/// [occurrence] backs `{#}` (1 for the first in a series). [fyStartMonth] is
/// the workspace's financial year start, so `{FY}` matches the tax pack.
String renderTokens(
  String pattern,
  DateTime date, {
  int occurrence = 1,
  int fyStartMonth = 4,
}) {
  if (pattern.isEmpty) return pattern;
  return pattern.replaceAllMapped(_tokenPattern, (m) {
    // `{{` is how you type a literal brace.
    if (m.group(0) == '{{') return '{';
    final name = m.group(1)!;
    final offset = int.tryParse(m.group(2) ?? '') ?? 0;
    final rendered = _render(name, offset, date, occurrence, fyStartMonth);
    // Unknown token: hand back exactly what was typed, braces and all.
    return rendered ?? m.group(0)!;
  });
}

String? _render(String name, int offset, DateTime date, int occurrence, int fyStartMonth) {
  // Offsets mean different things per family: months for month tokens, years
  // for year tokens, days for date tokens — whichever the token names.
  final byMonth = DateTime(date.year, date.month + offset, 1);
  final byYear = DateTime(date.year + offset, date.month, 1);
  final byDay = DateTime(date.year, date.month, date.day + offset);
  final byQuarter = DateTime(date.year, date.month + offset * 3, 1);

  switch (name.toUpperCase()) {
    // Same locale as formatDate(), so "{MMM}" and "{DATE}" never disagree
    // about how a month is spelt.
    case 'MMM':
      return DateFormat('MMM', 'en_IN').format(byMonth);
    case 'MMMM':
      return DateFormat('MMMM', 'en_IN').format(byMonth);
    case 'MM':
      return byMonth.month.toString().padLeft(2, '0');
    case 'YYYY':
      return byYear.year.toString();
    case 'YY':
      return (byYear.year % 100).toString().padLeft(2, '0');
    case 'D':
      return byDay.day.toString();
    case 'DD':
      return byDay.day.toString().padLeft(2, '0');
    case 'DATE':
      return formatDate(byDay);
    case 'Q':
      return 'Q${((byQuarter.month - 1) ~/ 3) + 1}';
    case 'FY':
      return financialYearOf(byYear, fyStartMonth);
    case '#':
      return (occurrence + offset).toString();
    default:
      return null;
  }
}

/// Insert [token] at [cursor] in [text], returning the new text and where the
/// cursor should land. Inserting at the caret rather than appending is the
/// difference between the chips being useful and being a nuisance.
({String text, int cursor}) insertToken(String text, int cursor, String token) {
  final at = (cursor < 0 || cursor > text.length) ? text.length : cursor;
  return (
    text: text.substring(0, at) + token + text.substring(at),
    cursor: at + token.length,
  );
}
