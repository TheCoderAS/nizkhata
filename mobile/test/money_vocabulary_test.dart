// The words the app uses for money owed in either direction.
//
// A ledger reads as a ledger: a debt is a payable or a receivable, and a drawn
// credit card is an outstanding balance. Conversational phrasing ("you owe",
// "they owe you") is deliberately absent, and this file is what keeps it that
// way — a string is easy to reintroduce by hand.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nizkhata/core/format.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN', null);
  });

  group('an account balance', () {
    test('writes money you are down in parentheses, with no word for it', () {
      // A drawn credit card and an overdrawn bank account read alike.
      expect(accountBalanceLabel('credit_card', -1000), '(₹1,000.00)');
      expect(accountBalanceLabel('bank', -1000), '(₹1,000.00)');
      expect(accountBalanceLabel('cash', -500), '(₹500.00)');
    });

    test('leaves a positive balance plain', () {
      expect(accountBalanceLabel('bank', 25000), '₹25,000.00');
      // A card in credit is an ordinary positive balance.
      expect(accountBalanceLabel('credit_card', 500), '₹500.00');
    });
  });

  group('the vocabulary across the app', () {
    test('no screen or widget says owe, owes or owed', () {
      final offenders = <String>[];
      final phrase = RegExp(r'''['"][^'"]*\b[Oo]we[sd]?\b[^'"]*['"]''');

      for (final dir in ['lib/screens', 'lib/widgets']) {
        for (final file in Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            // Comments explain the model, which still has an `owe`/`owed`
            // direction on disk. Only what reaches the screen is at issue.
            if (line.trimLeft().startsWith('//')) continue;
            // The stored direction values themselves are not user-facing.
            final withoutValues = line.replaceAll("'owed'", '').replaceAll("'owe'", '');
            if (phrase.hasMatch(withoutValues)) {
              offenders.add('${file.path}:${i + 1}  ${line.trim()}');
            }
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'Use payable / receivable / outstanding instead:\n'
              '${offenders.join('\n')}');
    });
  });
}
