// Credit card billing cycles.
//
// A card's balance in this app is a live running balance: spend on it and it
// goes further negative. That is the truth about what you owe today, but it is
// not what the bank asks you to pay. The bank draws a line on the statement
// day, and the amount payable is the balance as it stood at that moment —
// purchases made the following morning belong to the next bill.
//
// So a statement here is just that line: a date, the closing balance on it,
// and the day the payment is due. Everything else (spend since, the current
// balance) the rest of the app already knows.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/format.dart';
import '../data/derive.dart';
import '../data/models.dart';

/// One billing cycle: the period it covers, the day it was drawn, and the day
/// the payment is due.
class StatementCycle {
  /// First day covered — the day after the previous statement.
  final DateTime periodStart;

  /// The day the bill was drawn. Everything up to and including this day is on
  /// this bill.
  final DateTime statementDate;

  /// The day the payment must reach the bank.
  final DateTime paymentDue;

  const StatementCycle({
    required this.periodStart,
    required this.statementDate,
    required this.paymentDue,
  });
}

/// A day of the month, pulled back to the last day of a short month: a card
/// billed on the 31st bills on 28 February, not 3 March.
DateTime dayInMonth(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > lastDay ? lastDay : day);
}

/// The cycle whose statement date is the most recent one on or before [asOf].
///
/// Null when the card has no cycle set up.
StatementCycle? latestStatement(Account card, DateTime asOf) {
  if (!card.hasBillingCycle) return null;
  final day = card.statementDay!;
  var statement = dayInMonth(asOf.year, asOf.month, day);
  // Before this month's statement day: the live bill is last month's.
  if (statement.isAfter(DateTime(asOf.year, asOf.month, asOf.day))) {
    statement = dayInMonth(asOf.year, asOf.month - 1, day);
  }
  return cycleEndingOn(card, statement);
}

/// The cycle drawn on [statementDate], with its period and payment due date.
StatementCycle cycleEndingOn(Account card, DateTime statementDate) {
  final previous = dayInMonth(statementDate.year, statementDate.month - 1, card.statementDay!);
  return StatementCycle(
    periodStart: previous.add(const Duration(days: 1)),
    statementDate: statementDate,
    paymentDue: paymentDueAfter(statementDate, card.paymentDueDay!),
  );
}

/// The first [dueDay] strictly after the statement date.
///
/// This is what makes both cards work from the same two numbers: billed on the
/// 5th and due on the 25th stays in the month, billed on the 25th and due on
/// the 12th rolls into the next one.
DateTime paymentDueAfter(DateTime statementDate, int dueDay) {
  final sameMonth = dayInMonth(statementDate.year, statementDate.month, dueDay);
  if (sameMonth.isAfter(statementDate)) return sameMonth;
  return dayInMonth(statementDate.year, statementDate.month + 1, dueDay);
}

/// What the card owed at the close of [on]: positive is payable, zero or less
/// means nothing is (a credit balance after a refund, say).
///
/// This is the account's own balance as of that day, sign-flipped — not a sum
/// of the cycle's purchases. Anything carried forward from an unpaid bill is
/// therefore included, exactly as the bank would.
double statementOutstanding(
  Account card,
  List<Txn> txns,
  Map<String, Debt> debtsById,
  DateTime on,
) {
  final cutoff = DateTime(on.year, on.month, on.day).add(const Duration(days: 1));
  var balance = card.openingBalance;
  for (final txn in txns) {
    if (!txn.date.isBefore(cutoff)) continue;
    balance += accountDeltas(txn, debtsById)[card.id] ?? 0;
  }
  return roundMoney(-balance);
}

/// Money credited to the card after [since]: bill payments, and refunds.
///
/// Purchases made afterwards are not netted off. Paying a bill settles it
/// whatever you spend the next day — the new spending belongs to the next
/// statement, exactly as the bank treats it.
double creditedSince(
  Account card,
  List<Txn> txns,
  Map<String, Debt> debtsById,
  DateTime since,
) {
  final from = DateTime(since.year, since.month, since.day).add(const Duration(days: 1));
  var total = 0.0;
  for (final txn in txns) {
    if (txn.date.isBefore(from)) continue;
    final delta = accountDeltas(txn, debtsById)[card.id] ?? 0;
    if (delta > 0) total += delta;
  }
  return roundMoney(total);
}

/// Deterministic id for a card's bill, so every device and every run agrees on
/// which document a statement is, and none of them can create it twice.
String statementDueId(String accountId, DateTime statementDate) => 'stmt_${accountId}_${statementDate.year}'
    '${statementDate.month.toString().padLeft(2, '0')}'
    '${statementDate.day.toString().padLeft(2, '0')}';

/// The due document for a card's bill.
///
/// It carries a transfer line pointing at the card rather than an expense
/// line: the purchases were already counted as expenses when they were made,
/// and paying the bill only moves money from the bank to the card. Recording
/// it as spending would count the same rupee twice. The source account is left
/// for the payment sheet to ask, since only you know which account pays.
Map<String, dynamic> statementDueDoc(
  Account card,
  StatementCycle cycle,
  double outstanding,
) {
  final id = statementDueId(card.id, cycle.statementDate);
  return {
    'direction': 'payable',
    'title': '${card.name} bill',
    'amount': roundMoney(outstanding),
    'dueDate': Timestamp.fromDate(cycle.paymentDue),
    'note': 'Statement of ${formatDate(cycle.statementDate)}',
    'lines': [
      {
        'lineId': '${id}_out',
        'type': 'transfer_out',
        'amount': roundMoney(outstanding),
        'toAccountId': card.id,
      },
      {
        'lineId': '${id}_in',
        'type': 'transfer_in',
        'amount': roundMoney(outstanding),
        'toAccountId': card.id,
      },
    ],
    // A statement is not a recurring due: each one is generated from its own
    // cycle, so the recurrence engine must keep its hands off them.
    'statementAccountId': card.id,
    'statementDate': Timestamp.fromDate(cycle.statementDate),
  };
}

/// A write the sync should make for a card's current bill.
class StatementDuePlan {
  final String dueId;
  final Map<String, dynamic> doc;

  /// True when the due already exists and only its amount needs correcting.
  final bool isUpdate;
  const StatementDuePlan(this.dueId, this.doc, {this.isUpdate = false});
}

/// The bill dues that ought to exist right now, and the ones whose amount has
/// drifted since they were raised.
///
/// Only the CURRENT statement of each card is ever generated. Opening the app
/// after three quiet months should not fill the dues list with three old bills
/// you have long since paid; the live one is the one that needs paying.
///
/// A bill is left alone once you have paid anything against it, or once you
/// have cancelled it. Otherwise its amount is kept in step with the ledger, so
/// a purchase entered late — a statement imported a week after the fact — is
/// reflected in what the bill asks for.
List<StatementDuePlan> statementDuePlans({
  required List<Account> accounts,
  required List<Due> dues,
  required List<Txn> txns,
  required Map<String, Debt> debtsById,
  required double Function(String dueId) settledOf,
  required DateTime now,
}) {
  final byId = {for (final d in dues) d.id: d};
  final out = <StatementDuePlan>[];

  for (final card in accounts) {
    final cycle = latestStatement(card, now);
    if (cycle == null) continue;

    final owed = statementOutstanding(card, txns, debtsById, cycle.statementDate);
    if (owed <= 0.005) continue; // nothing billed, or the card is in credit

    final id = statementDueId(card.id, cycle.statementDate);
    final doc = statementDueDoc(card, cycle, owed);
    final existing = byId[id];

    if (existing == null) {
      // The live statement can be one that has already been paid: the first
      // sync after a cycle is set up looks back at last month's, and by then
      // that bill is usually settled. Raising it would ask for money already
      // sent, dated in the past, so it would land overdue as well as wrong.
      if (owed - creditedSince(card, txns, debtsById, cycle.statementDate) <= 0.005) {
        continue;
      }
      out.add(StatementDuePlan(id, doc));
      continue;
    }
    if (existing.status == 'cancelled') continue; // dismissed on purpose
    if (settledOf(id) > 0.005) continue; // part paid: the figure is now history
    if ((existing.amount - owed).abs() > 0.005) {
      out.add(StatementDuePlan(id, doc, isUpdate: true));
    }
  }
  return out;
}
