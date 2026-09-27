// Month tokens are spelt the way formatDate() spells the month, whichever
// English the phone uses. "{MMM}" and "{DATE}" side by side in one title must
// never disagree ("Sep" next to "3 Sept 2026").

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nizkhata/core/format.dart';
import 'package:nizkhata/services/title_tokens.dart';

void main() {
  setUpAll(() async => initializeDateFormatting());

  // AppLocale.date is global; put back the default every other test assumes.
  tearDown(() => AppLocale.date = 'en_IN');

  final sep2026 = DateTime(2026, 9, 3);

  test('an Indian phone keeps "Sept", as always', () {
    expect(renderTokens('{MMM} | {DATE}', sep2026), 'Sept | 3 Sept 2026');
  });

  test('an American phone writes "Sep", in the month token and the date alike', () {
    AppLocale.date = 'en_US';
    expect(renderTokens('{MMM} | {DATE}', sep2026), 'Sep | Sep 3, 2026');
    expect(renderTokens('{MMMM}', sep2026), 'September');
  });

  test('a British phone agrees with its own date format too', () {
    AppLocale.date = 'en_GB';
    final date = formatDate(sep2026);
    final month = renderTokens('{MMM}', sep2026);
    expect(date, contains(month));
  });
}
