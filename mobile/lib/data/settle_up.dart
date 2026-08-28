// Settle-up: one transaction that nets out every open debt with a contact.
// Each open debt contributes a repayment line for its full outstanding; the
// existing line math (accountDeltas/computeTotal) then makes the transaction's
// signed total exactly the net position — money in when they owed you more,
// money out when you owed them more.

import 'derive.dart';
import 'models.dart';

class SettleUpPlan {
  final List<Map<String, dynamic>> lines;
  final double signedTotal; // + money in, − money out
  final List<Debt> debts; // the debts being closed, for display
  SettleUpPlan(this.lines, this.signedTotal, this.debts);
  bool get isEmpty => lines.isEmpty;
}

SettleUpPlan buildSettleUpPlan(
  String contactId,
  List<Debt> allDebts,
  List<Txn> txns, {
  required int lineIdSeed,
}) {
  final lines = <Map<String, dynamic>>[];
  final closing = <Debt>[];
  final debtsById = <String, Debt>{};
  var i = 0;
  for (final debt in allDebts) {
    if (debt.contactId != contactId || debt.status != 'open') continue;
    final outstanding = debtOutstanding(debt, txns);
    if (outstanding <= 0.005) continue;
    debtsById[debt.id] = debt;
    closing.add(debt);
    lines.add({
      'lineId': 'settle_${lineIdSeed}_l${i++}',
      'type': 'repayment',
      'amount': roundMoney(outstanding),
      'debtId': debt.id,
      'note': 'Settle-up',
    });
  }
  if (lines.isEmpty) return SettleUpPlan(const [], 0, const []);
  final total = computeTotal(
    [for (final l in lines) TxnLine.fromMap(l)],
    debtsById,
  );
  return SettleUpPlan(lines, total, closing);
}
