import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nizkhata/core/format.dart';
import 'package:nizkhata/data/models.dart';
import 'package:nizkhata/services/statement_cycle.dart';

Account _card({
  String id = 'cc1',
  String name = 'HDFC Regalia',
  double opening = 0,
  int? statementDay = 5,
  int? paymentDueDay = 25,
}) =>
    Account(
      id: id,
      workspaceId: 'ws',
      name: name,
      type: 'credit_card',
      openingBalance: opening,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
    );

Txn _spend(String id, DateTime date, double amount, {String account = 'cc1'}) => Txn(
      id: id,
      workspaceId: 'ws',
      date: date,
      accountId: account,
      totalAmount: -amount,
      hasSplit: false,
      financialYear: '2026-27',
      lines: [TxnLine(lineId: '${id}l', type: 'expense', amount: amount)],
    );

/// A bill payment: money leaves the bank and lands on the card.
Txn _payment(String id, DateTime date, double amount) => Txn(
      id: id,
      workspaceId: 'ws',
      date: date,
      accountId: 'bank',
      totalAmount: -amount,
      hasSplit: false,
      financialYear: '2026-27',
      lines: [
        TxnLine(lineId: '${id}a', type: 'transfer_out', amount: amount, toAccountId: 'cc1'),
        TxnLine(lineId: '${id}b', type: 'transfer_in', amount: amount, toAccountId: 'cc1'),
      ],
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN', null);
  });

  group('which statement is live', () {
    test('after the statement day it is this month\'s', () {
      final c = latestStatement(_card(), DateTime(2026, 9, 20))!;
      expect(c.statementDate, DateTime(2026, 9, 5));
      expect(c.periodStart, DateTime(2026, 8, 6));
      expect(c.paymentDue, DateTime(2026, 9, 25));
    });

    test('on the statement day itself it is that day', () {
      final c = latestStatement(_card(), DateTime(2026, 9, 5))!;
      expect(c.statementDate, DateTime(2026, 9, 5));
    });

    test('before the statement day it is last month\'s', () {
      final c = latestStatement(_card(), DateTime(2026, 9, 3))!;
      expect(c.statementDate, DateTime(2026, 8, 5));
      expect(c.paymentDue, DateTime(2026, 8, 25));
    });

    test('in January it looks back into December', () {
      final c = latestStatement(_card(), DateTime(2027, 1, 3))!;
      expect(c.statementDate, DateTime(2026, 12, 5));
      expect(c.periodStart, DateTime(2026, 11, 6));
      expect(c.paymentDue, DateTime(2026, 12, 25));
    });

    test('a card with no cycle set up has no statement', () {
      expect(latestStatement(_card(statementDay: null), DateTime(2026, 9, 20)), isNull);
      expect(latestStatement(_card(paymentDueDay: null), DateTime(2026, 9, 20)), isNull);
      final notACard = Account(id: 'a1', workspaceId: 'ws', name: 'Savings', type: 'bank', openingBalance: 0);
      expect(latestStatement(notACard, DateTime(2026, 9, 20)), isNull);
    });
  });

  group('short months', () {
    test('a card billed on the 31st bills on the last day of February', () {
      final c = latestStatement(_card(statementDay: 31, paymentDueDay: 20), DateTime(2026, 3, 1))!;
      expect(c.statementDate, DateTime(2026, 2, 28));
      // 2028 is a leap year.
      final leap = latestStatement(_card(statementDay: 31, paymentDueDay: 20), DateTime(2028, 3, 1))!;
      expect(leap.statementDate, DateTime(2028, 2, 29));
    });

    test('the period start follows the same clamping', () {
      final c = latestStatement(_card(statementDay: 31, paymentDueDay: 20), DateTime(2026, 3, 31))!;
      expect(c.statementDate, DateTime(2026, 3, 31));
      // February ended on the 28th, so March opened on the 1st.
      expect(c.periodStart, DateTime(2026, 3, 1));
    });
  });

  group('when the payment is due', () {
    test('a due day after the statement day stays in the month', () {
      expect(paymentDueAfter(DateTime(2026, 9, 5), 25), DateTime(2026, 9, 25));
    });

    test('a due day before the statement day rolls into the next month', () {
      expect(paymentDueAfter(DateTime(2026, 9, 25), 12), DateTime(2026, 10, 12));
      // Across the year boundary too.
      expect(paymentDueAfter(DateTime(2026, 12, 25), 12), DateTime(2027, 1, 12));
    });

    test('a due day equal to the statement day means the next month', () {
      expect(paymentDueAfter(DateTime(2026, 9, 5), 5), DateTime(2026, 10, 5));
    });
  });

  group('what is owed on the statement', () {
    final txns = [
      _spend('t1', DateTime(2026, 8, 20), 3000),
      _spend('t2', DateTime(2026, 9, 2), 1500),
      // The morning after the statement — next month's problem.
      _spend('t3', DateTime(2026, 9, 6), 900),
    ];

    test('counts everything up to and including the statement day', () {
      final owed = statementOutstanding(_card(), txns, const {}, DateTime(2026, 9, 5));
      expect(owed, 4500);
    });

    test('a purchase on the statement day itself is on that bill', () {
      final owed = statementOutstanding(
        _card(),
        [...txns, _spend('t4', DateTime(2026, 9, 5), 100)],
        const {},
        DateTime(2026, 9, 5),
      );
      expect(owed, 4600);
    });

    test('carries forward what an earlier unpaid bill left behind', () {
      // Opening balance is the card's own: negative means already owed.
      final owed = statementOutstanding(_card(opening: -2000), txns, const {}, DateTime(2026, 9, 5));
      expect(owed, 6500);
    });

    test('a payment during the cycle reduces it', () {
      final owed = statementOutstanding(
        _card(),
        [...txns, _payment('p1', DateTime(2026, 8, 25), 3000)],
        const {},
        DateTime(2026, 9, 5),
      );
      expect(owed, 1500);
    });

    test('a fully paid card owes nothing', () {
      final owed = statementOutstanding(
        _card(),
        [_spend('t1', DateTime(2026, 8, 20), 3000), _payment('p1', DateTime(2026, 8, 25), 3000)],
        const {},
        DateTime(2026, 9, 5),
      );
      expect(owed, 0);
    });

    test('a refund can leave the card in credit, which is not a bill', () {
      final owed = statementOutstanding(
        _card(),
        [_spend('t1', DateTime(2026, 8, 20), 3000), _payment('p1', DateTime(2026, 8, 25), 4000)],
        const {},
        DateTime(2026, 9, 5),
      );
      expect(owed, -1000);
    });

    test('transactions on other accounts are none of its business', () {
      final owed = statementOutstanding(
        _card(),
        [...txns, _spend('other', DateTime(2026, 9, 1), 7000, account: 'bank')],
        const {},
        DateTime(2026, 9, 5),
      );
      expect(owed, 4500);
    });
  });

  group('the bill due', () {
    final cycle = StatementCycle(
      periodStart: DateTime(2026, 8, 6),
      statementDate: DateTime(2026, 9, 5),
      paymentDue: DateTime(2026, 9, 25),
    );

    test('is payable on the payment due date, for the amount owed', () {
      final doc = statementDueDoc(_card(), cycle, 4500);
      expect(doc['direction'], 'payable');
      expect(doc['amount'], 4500);
      expect((doc['dueDate'] as Timestamp).toDate(), DateTime(2026, 9, 25));
      expect(doc['title'], 'HDFC Regalia bill');
      expect(doc['note'], 'Statement of 5 Sept 2026');
    });

    test('settles as a transfer to the card, never as an expense', () {
      final lines = (statementDueDoc(_card(), cycle, 4500)['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines.map((l) => l['type']), ['transfer_out', 'transfer_in']);
      // Both halves point at the card and carry the same amount.
      expect(lines.every((l) => l['toAccountId'] == 'cc1'), true);
      expect(lines.every((l) => l['amount'] == 4500), true);
      // Nothing here would ever be read as spending.
      expect(lines.any((l) => l['type'] == 'expense'), false);
    });

    test('carries no source account: only you know what pays it', () {
      expect(statementDueDoc(_card(), cycle, 4500)['accountId'], isNull);
    });

    test('is not a recurring due — each statement generates its own', () {
      final doc = statementDueDoc(_card(), cycle, 4500);
      expect(doc['recurrence'], isNull);
      expect(doc['recurrenceId'], isNull);
    });

    test('is identified by the card and the statement date', () {
      expect(statementDueId('cc1', DateTime(2026, 9, 5)), 'stmt_cc1_20260905');
      // Two devices generating the same bill land on the same document.
      expect(
        statementDueDoc(_card(), cycle, 4500)['statementDate'],
        statementDueDoc(_card(), cycle, 9999)['statementDate'],
      );
    });
  });

  group('what the sync decides to write', () {
    final now = DateTime(2026, 9, 20);
    final txns = [_spend('t1', DateTime(2026, 8, 20), 3000)];
    double nothingPaid(String _) => 0;

    Due bill({double amount = 3000, String status = 'open'}) => Due(
          id: statementDueId('cc1', DateTime(2026, 9, 5)),
          workspaceId: 'ws',
          direction: 'payable',
          title: 'HDFC Regalia bill',
          amount: amount,
          dueDate: DateTime(2026, 9, 25),
          status: status,
        );

    List<StatementDuePlan> plans({
      List<Due> dues = const [],
      List<Txn>? on,
      double Function(String)? settled,
      List<Account>? accounts,
      DateTime? asOf,
    }) =>
        statementDuePlans(
          accounts: accounts ?? [_card()],
          dues: dues,
          txns: on ?? txns,
          debtsById: const {},
          settledOf: settled ?? nothingPaid,
          now: asOf ?? now,
        );

    // The 4th, so the live statement is LAST month's (the 5th has not come
    // round yet). This is the shape of the first sync after a cycle is set up.
    final beforeThisMonthsStatement = DateTime(2026, 9, 4);
    final billedInAugust = _spend('t1', DateTime(2026, 7, 20), 5000);

    test('raises the bill for a card that owes something', () {
      final p = plans().single;
      expect(p.dueId, 'stmt_cc1_20260905');
      expect(p.isUpdate, false);
      expect(p.doc['amount'], 3000);
    });

    test('raises nothing twice: the bill already exists and agrees', () {
      expect(plans(dues: [bill()]), isEmpty);
    });

    test('corrects the amount when a purchase lands in the cycle late', () {
      final later = [...txns, _spend('t2', DateTime(2026, 9, 1), 500)];
      final p = plans(dues: [bill()], on: later).single;
      expect(p.isUpdate, true);
      expect(p.doc['amount'], 3500);
    });

    test('leaves a part paid bill alone rather than moving the goalposts', () {
      final later = [...txns, _spend('t2', DateTime(2026, 9, 1), 500)];
      expect(plans(dues: [bill()], on: later, settled: (_) => 1000), isEmpty);
    });

    test('respects a bill you cancelled', () {
      expect(
          plans(dues: [
            bill(status: 'cancelled')
          ], on: [
            ...txns,
            _spend('t2', DateTime(2026, 9, 1), 500),
          ]),
          isEmpty);
    });

    test('raises nothing on a card that owes nothing', () {
      expect(
          plans(on: [_spend('t1', DateTime(2026, 8, 20), 3000), _payment('p1', DateTime(2026, 8, 25), 3000)]),
          isEmpty);
    });

    test('an unpaid bill from before you set the cycle up is still raised', () {
      // You do owe it, and it is overdue, so it belongs in the list.
      final p = plans(on: [billedInAugust], asOf: beforeThisMonthsStatement).single;
      expect(p.dueId, 'stmt_cc1_20260805');
      expect(p.doc['amount'], 5000);
    });

    test('is not raised when it was already paid after the statement', () {
      // The commonest case of all: the cycle is set up mid month, so the live
      // statement is last month's, and that bill was paid weeks ago. Asking
      // for it again would post an overdue demand for money already sent.
      expect(
        plans(
          on: [billedInAugust, _payment('p1', DateTime(2026, 8, 20), 5000)],
          asOf: beforeThisMonthsStatement,
        ),
        isEmpty,
      );
    });

    test('is still raised when the payment fell short of the bill', () {
      final p = plans(
        on: [billedInAugust, _payment('p1', DateTime(2026, 8, 20), 3000)],
        asOf: beforeThisMonthsStatement,
      ).single;
      // It asks for what was billed; the part payment is recorded against it.
      expect(p.doc['amount'], 5000);
    });

    test('spending after the statement does not revive a paid bill', () {
      // Paid in full, then spent again. The new spending belongs to the next
      // statement and must not make this one look unpaid.
      expect(
        plans(
          on: [
            billedInAugust,
            _payment('p1', DateTime(2026, 8, 20), 5000),
            _spend('t2', DateTime(2026, 8, 28), 2000),
          ],
          asOf: beforeThisMonthsStatement,
        ),
        isEmpty,
      );
    });

    test('only the current statement, never a backlog of old ones', () {
      // Six months of spending on a card whose cycle has rolled six times.
      final old = [for (var m = 4; m <= 9; m++) _spend('t$m', DateTime(2026, m, 2), 1000)];
      final raised = plans(on: old);
      expect(raised.length, 1);
      expect(raised.single.dueId, 'stmt_cc1_20260905');
    });

    test('ignores accounts that are not cards, and cards with no cycle', () {
      final accounts = [
        _card(statementDay: null),
        Account(id: 'bank', workspaceId: 'ws', name: 'Savings', type: 'bank', openingBalance: -5000),
      ];
      expect(plans(accounts: accounts), isEmpty);
    });

    test('handles two cards independently', () {
      final second = _card(id: 'cc2', name: 'Amex', statementDay: 18, paymentDueDay: 8);
      final both = plans(
        accounts: [_card(), second],
        on: [...txns, _spend('t9', DateTime(2026, 9, 10), 800, account: 'cc2')],
      );
      expect(both.map((p) => p.dueId), ['stmt_cc1_20260905', 'stmt_cc2_20260918']);
      expect(both.last.doc['amount'], 800);
      // Amex bills on the 18th and is due on the 8th, so next month.
      expect((both.last.doc['dueDate'] as Timestamp).toDate(), DateTime(2026, 10, 8));
    });
  });

  group('how a cycle day reads', () {
    test('takes the ordinal people would say out loud', () {
      expect(ordinalDay(1), '1st');
      expect(ordinalDay(2), '2nd');
      expect(ordinalDay(3), '3rd');
      expect(ordinalDay(4), '4th');
      expect(ordinalDay(21), '21st');
      expect(ordinalDay(22), '22nd');
      expect(ordinalDay(23), '23rd');
      expect(ordinalDay(31), '31st');
    });

    test('the teens break the pattern their last digit suggests', () {
      expect(ordinalDay(11), '11th');
      expect(ordinalDay(12), '12th');
      expect(ordinalDay(13), '13th');
    });
  });
}
