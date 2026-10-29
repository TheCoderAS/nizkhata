// A part repayment must leave a debt open. Taken from a real case: 16,000
// lent, 15,000 received back, and the debt was closed with 1,000 still due.

import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/data/derive.dart';

void main() {
  test('a part repayment leaves the rest to pay', () {
    expect(repaymentSettles(16000, 15000), false);
  });

  test('paying exactly what is left settles it', () {
    expect(repaymentSettles(16000, 16000), true);
    expect(repaymentSettles(1000, 1000), true);
  });

  test('paying more than is left settles it', () {
    expect(repaymentSettles(1000, 1200), true);
  });

  test('a paisa of rounding does not keep a debt open', () {
    expect(repaymentSettles(1000.004, 1000), true);
  });

  test('the balance read after the write would have closed it, which is the bug', () {
    // What the old code computed: the cached balance already had the 15,000
    // taken off (1,000 left), and then took it off again.
    const afterWrite = 1000.0;
    expect(afterWrite - 15000 <= 0.005, true);
    // Reading the balance before the write gives the right answer.
    expect(repaymentSettles(16000, 15000), false);
  });
}
