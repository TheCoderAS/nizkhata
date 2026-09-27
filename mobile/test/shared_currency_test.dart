// The shared ledger across currencies.
//
// Two people sharing expenses may keep their books in different currencies.
// An entry is a figure in its creator's currency, so it is read in that
// currency by both sides, balances never add a rupee to a dollar, and nothing
// is written into books kept in another currency.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/core/currency.dart';
import 'package:nizkhata/data/mutations.dart' show Actor;
import 'package:nizkhata/data/shared_mutations.dart';

const me = 'me';
const them = 'them';

SharedEntry entry({
  String id = 'e',
  double amount = 100,
  String? currency,
  String payer = me,
  String status = 'accepted',
  String kind = 'expense',
}) {
  return SharedEntry.fromMap(id, {
    'connectionId': 'c',
    'kind': kind,
    'uids': [me, them],
    'creatorUid': payer,
    'counterpartyUid': payer == me ? them : me,
    'names': {me: 'Me', them: 'Them'},
    'payerUid': payer,
    'description': 'Dinner',
    'amount': amount,
    'status': status,
    'pendingForUids': <String>[],
    if (currency != null) 'currency': currency,
  });
}

SharedMutations mutations() =>
    SharedMutations(uid: me, displayName: 'Me', email: 'me@x.com', by: const Actor(me, 'Me'));

void main() {
  tearDown(() => MoneyContext.currency = 'INR');

  group('an entry knows its currency', () {
    test('an entry from before the field existed is INR', () {
      expect(entry().currency, 'INR');
    });

    test('a stamped currency is read as stored', () {
      expect(entry(currency: 'USD').currency, 'USD');
      expect(entry(currency: 'jpy').currency, 'JPY');
    });

    test('something unreadable falls back to INR, not to the reader\'s currency', () {
      expect(sharedEntryCurrency(42), 'INR');
      expect(sharedEntryCurrency('DOLLARS'), 'INR');
      expect(sharedEntryCurrency(null), 'INR');
    });
  });

  group('balances', () {
    test('a rupee balance and a dollar balance with the same person stay apart', () {
      final balances = sharedBalances(me, [
        entry(id: 'a', amount: 500),
        entry(id: 'b', amount: 20, currency: 'USD'),
      ]);
      expect(balances, hasLength(2));
      final byCurrency = {for (final b in balances) b.currency: b.net};
      expect(byCurrency, {'INR': 500.0, 'USD': 20.0});
      expect(balances.every((b) => b.uid == them), isTrue);
    });

    test('old unstamped entries and new INR ones are one balance', () {
      final balances = sharedBalances(me, [
        entry(id: 'a', amount: 300),
        entry(id: 'b', amount: 200, currency: 'INR'),
      ]);
      expect(balances.single.currency, 'INR');
      expect(balances.single.net, 500);
    });

    test('each balance rounds in its own currency, whatever the workspace is', () {
      MoneyContext.currency = 'KWD'; // three decimals in the active books
      final balances = sharedBalances(me, [
        entry(id: 'a', amount: 100.4, currency: 'JPY'),
        entry(id: 'b', amount: 100.4, currency: 'JPY'),
      ]);
      expect(balances.single.net, 201); // whole yen
    });

    test('a balance that nets to nothing in its currency is dropped', () {
      final balances = sharedBalances(me, [
        entry(id: 'a', amount: 50, currency: 'USD'),
        entry(id: 'b', amount: 50, currency: 'USD', payer: them),
      ]);
      expect(balances, isEmpty);
    });
  });

  group('nothing is recorded in books of another currency', () {
    test('the note explains, in plain words', () {
      expect(sharedCurrencyNote('USD', 'USD'), isNull);
      final note = sharedCurrencyNote('USD', 'INR')!;
      expect(note, contains('USD'));
      expect(note, contains('INR'));
      expect(note, isNot(contains('—')));
      expect(note, isNot(matches(RegExp(r'\b[Oo]we[sd]?\b'))));
    });

    // Each guard runs before anything touches Firestore, which is not set up
    // here: reaching it would throw something other than the mismatch.
    test('accepting a dollar expense into rupee books is refused', () async {
      await expectLater(
        mutations().acceptSharedExpense(
          entry: entry(currency: 'USD', payer: them, status: 'pending'),
          workspaceId: 'ws',
          bookCurrency: 'INR',
          fyStartMonth: 4,
          contacts: const [],
          debts: const [],
        ),
        throwsA(isA<SharedCurrencyMismatch>()),
      );
    });

    test('an old unstamped entry is refused by dollar books too', () async {
      await expectLater(
        mutations().acceptSharedExpense(
          entry: entry(payer: them, status: 'pending'),
          workspaceId: 'ws',
          bookCurrency: 'USD',
          fyStartMonth: 1,
          contacts: const [],
          debts: const [],
        ),
        throwsA(isA<SharedCurrencyMismatch>()),
      );
    });

    test('accepting a settlement in another currency is refused', () async {
      await expectLater(
        mutations().acceptSettlement(
          entry: entry(currency: 'EUR', payer: them, status: 'pending', kind: 'settlement'),
          workspaceId: 'ws',
          bookCurrency: 'INR',
          fyStartMonth: 4,
          contacts: const [],
          debts: const [],
          accountId: 'acc',
        ),
        throwsA(isA<SharedCurrencyMismatch>()),
      );
    });

    test('resolving a conflict from books in another currency is refused', () async {
      for (final mode in ['absorb', 'remove']) {
        await expectLater(
          mutations().resolveConflict(
            entry: entry(currency: 'USD', status: 'rejected'),
            mode: mode,
            reflectionTxnId: 't',
            fyStartMonth: 4,
            date: DateTime(2026, 1, 1),
            accountId: 'acc',
            workspaceId: 'ws',
            bookCurrency: 'INR',
          ),
          throwsA(isA<SharedCurrencyMismatch>()),
        );
      }
    });
  });

  test('the shared screen takes its currency from the workspace, not a literal', () {
    final src = File('lib/screens/shared_screen.dart').readAsStringSync();
    expect(src, isNot(contains("prefixText: '₹")));
    expect(src, isNot(contains("baseCurrency ?? 'INR'")));
  });
}
