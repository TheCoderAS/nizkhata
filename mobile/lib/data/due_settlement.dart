// Materialize a settlement transaction from a due — the single source of the
// "due IS the transaction blueprint" rule, shared by the manual Record-payment
// sheet and the statement-import due matcher. Partial payments scale every
// line (and its TDS) proportionally; legacy dues without lines produce one
// typed line.

import 'derive.dart';
import 'models.dart';

class DueSettlementDraft {
  final List<Map<String, dynamic>> lines;
  final double signedTotal;
  DueSettlementDraft(this.lines, this.signedTotal);
}

DueSettlementDraft buildDueSettlement(
  Due due,
  double amount,
  Map<String, Debt> debtsById, {
  required int lineIdSeed,
}) {
  if (due.lines.isNotEmpty && due.amount > 0.005) {
    final f = amount / due.amount;
    var i = 0;
    final lines = due.lines.map((l) {
      final m = l.toMap();
      m['lineId'] = 'due_${lineIdSeed}_l${i++}';
      m['amount'] = roundMoney(l.amount * f);
      final tax = m['tax'];
      if (tax is Map && tax['tdsAmount'] is num) {
        final t2 = Map<String, dynamic>.from(tax);
        t2['tdsAmount'] = roundMoney((t2['tdsAmount'] as num).toDouble() * f);
        m['tax'] = t2;
      }
      return m;
    }).toList();
    final unit = computeTotal(due.lines, debtsById);
    return DueSettlementDraft(lines, roundMoney(unit.sign * amount));
  }
  return DueSettlementDraft(
    [
      {
        'lineId': 'due_$lineIdSeed',
        'type': due.direction == 'payable' ? 'expense' : 'income',
        'amount': amount,
        'categoryId': due.categoryId,
      },
    ],
    roundMoney(due.direction == 'payable' ? -amount : amount),
  );
}
