// Whether a debt still counts as outstanding.
//
// The stored `status` field is only written when a debt is settled through the
// repayment sheet. Clear one any other way and the field still says "open"
// while the balance says zero, which is how a fully repaid loan kept turning
// up under the Outstanding filter.

import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/data/derive.dart';
import 'package:nizkhata/data/models.dart';

Debt _debt({String status = 'open', String direction = 'owe'}) => Debt(
      id: 'd1',
      workspaceId: 'ws',
      contactId: 'c1',
      direction: direction,
      principal: 20000,
      status: status,
      purpose: 'personal',
    );

void main() {
  test('a balance of zero is settled, whatever the stored field says', () {
    expect(debtStatusFrom(_debt(), 0), 'settled');
    expect(debtIsOutstanding(_debt(), 0), false);
    // A rounding crumb is nil.
    expect(debtStatusFrom(_debt(), 0.004), 'settled');
  });

  test('a balance still standing is outstanding', () {
    expect(debtStatusFrom(_debt(), 16000), 'open');
    expect(debtIsOutstanding(_debt(), 16000), true);
  });

  test('the stored field can close a debt early, but never reopen a clear one', () {
    // Written off, or settled in kind: closed while a balance remains.
    expect(debtStatusFrom(_debt(status: 'settled'), 16000), 'settled');
    expect(debtIsOutstanding(_debt(status: 'settled'), 16000), false);
    // And the reverse cannot happen: zero is settled even when stored open.
    expect(debtStatusFrom(_debt(status: 'open'), 0), 'settled');
  });

  test('an overpaid debt keeps showing, because that is a discrepancy', () {
    // Repaid more than was borrowed: either the other side owes you now, or
    // something was entered twice. Quietly filing it as settled would hide it.
    expect(debtStatusFrom(_debt(), -500), 'open');
    expect(debtIsOutstanding(_debt(), -500), true);
  });

  test('an empty stored status still reads as open when money is left', () {
    expect(debtStatusFrom(_debt(status: ''), 16000), 'open');
  });
}
