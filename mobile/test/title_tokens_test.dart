import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nizkhata/services/title_tokens.dart';

void main() {
  setUpAll(() async {
    // formatDate() renders in en_IN, which the app initialises at startup.
    await initializeDateFormatting('en_IN', null);
  });

  final sep2026 = DateTime(2026, 9, 3);

  group('rendering', () {
    test('leaves plain text alone', () {
      expect(renderTokens('RD Payment', sep2026), 'RD Payment');
    });

    test('fills the month, year and date tokens', () {
      expect(renderTokens('RD Payment - {MMM}', sep2026), 'RD Payment - Sept');
      expect(renderTokens('{MMMM} {YYYY}', sep2026), 'September 2026');
      expect(renderTokens('{MM}/{YY}', sep2026), '09/26');
      expect(renderTokens('{D} and {DD}', sep2026), '3 and 03');
      expect(renderTokens('{DATE}', sep2026), '3 Sept 2026');
      expect(renderTokens('{Q}', sep2026), 'Q3');
    });

    test('is case insensitive so {mmm} works like {MMM}', () {
      expect(renderTokens('{mmm} {yyyy}', sep2026), 'Sept 2026');
    });

    test('renders every occurrence of a repeated token', () {
      expect(renderTokens('{MMM}-{MMM}', sep2026), 'Sept-Sept');
    });
  });

  group('offsets', () {
    test('shift months for month tokens, including across a year boundary', () {
      expect(renderTokens('{MMM-1}', sep2026), 'Aug');
      expect(renderTokens('{MMM+1}', sep2026), 'Oct');
      // The RD case: a payment made in January is for December.
      expect(renderTokens('{MMM-1} {YYYY}', DateTime(2027, 1, 5)), 'Dec 2027');
      expect(renderTokens('{MMM+1}', DateTime(2026, 12, 5)), 'Jan');
      expect(renderTokens('{MM-1}', DateTime(2026, 1, 5)), '12');
    });

    test('shift years for year tokens', () {
      expect(renderTokens('{YYYY-1}', sep2026), '2025');
      expect(renderTokens('{YYYY+1}', sep2026), '2027');
      expect(renderTokens('{YY+1}', sep2026), '27');
    });

    test('shift days for day tokens', () {
      expect(renderTokens('{D+1}', sep2026), '4');
      expect(renderTokens('{DD-3}', sep2026), '31'); // back into August
      expect(renderTokens('{DATE+1}', sep2026), '4 Sept 2026');
    });

    test('shift whole quarters for {Q}', () {
      expect(renderTokens('{Q+1}', sep2026), 'Q4');
      expect(renderTokens('{Q-1}', sep2026), 'Q2');
      // December + one quarter lands in the next year's first quarter.
      expect(renderTokens('{Q+1}', DateTime(2026, 12, 1)), 'Q1');
    });

    test('shift the number for {#}', () {
      expect(renderTokens('Instalment {#}', sep2026, occurrence: 7), 'Instalment 7');
      expect(renderTokens('{#+1}', sep2026, occurrence: 7), '8');
      expect(renderTokens('{#-1}', sep2026, occurrence: 7), '6');
    });
  });

  group('financial year', () {
    test('follows the workspace FY start month', () {
      // April start: September 2026 sits in 2026-27.
      expect(renderTokens('{FY}', sep2026), '2026-27');
      // January start: it is simply the calendar year.
      expect(renderTokens('{FY}', sep2026, fyStartMonth: 1), '2026');
    });

    test('a month before the FY start belongs to the previous FY', () {
      expect(renderTokens('{FY}', DateTime(2026, 3, 31)), '2025-26');
    });

    test('offsets move the FY by whole years', () {
      expect(renderTokens('{FY-1}', sep2026), '2025-26');
      expect(renderTokens('{FY+1}', sep2026), '2027-28');
    });
  });

  group('forgiving parsing', () {
    test('an unknown token is left on screen exactly as typed', () {
      expect(renderTokens('{MON} rent', sep2026), '{MON} rent');
      expect(renderTokens('{}', sep2026), '{}');
      expect(renderTokens('{MMM', sep2026), '{MMM');
    });

    test('an unknown token beside a known one does not swallow the known one', () {
      expect(renderTokens('{MON} {MMM}', sep2026), '{MON} Sept');
    });

    test('{{ escapes a literal brace', () {
      expect(renderTokens('{{MMM}', sep2026), '{MMM}');
      expect(renderTokens('a {{ b', sep2026), 'a { b');
    });

    test('an empty pattern stays empty', () {
      expect(renderTokens('', sep2026), '');
    });
  });

  group('hasTokens', () {
    test('is true only for tokens the renderer understands', () {
      expect(hasTokens('RD Payment - {MMM}'), true);
      expect(hasTokens('RD Payment - {MMM-1}'), true);
      expect(hasTokens('RD Payment - Aug'), false);
      expect(hasTokens('{MON}'), false);
      expect(hasTokens(null), false);
      expect(hasTokens(''), false);
    });
  });

  group('insertToken', () {
    test('inserts at the caret and leaves the caret after the token', () {
      final r = insertToken('RD  payment', 3, '{MMM}');
      expect(r.text, 'RD {MMM} payment');
      expect(r.cursor, 8);
    });

    test('appends when the field has never been focused', () {
      final r = insertToken('RD payment', -1, '{MMM}');
      expect(r.text, 'RD payment{MMM}');
      expect(r.cursor, 15);
    });

    test('appends when the caret is past the end', () {
      final r = insertToken('RD', 99, '{MMM}');
      expect(r.text, 'RD{MMM}');
      expect(r.cursor, 7);
    });
  });

  group('the picker list', () {
    test('every offered token actually renders', () {
      for (final spec in kTitleTokens) {
        expect(hasTokens(spec.token), true, reason: '${spec.token} is not recognised');
        expect(renderTokens(spec.token, sep2026), isNot(spec.token),
            reason: '${spec.token} rendered as itself');
      }
    });

    test('the primary chips are a prefix of the full list', () {
      expect(kPrimaryTokenCount, lessThan(kTitleTokens.length));
    });
  });
}
