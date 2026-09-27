// GST is India's. A tax line in any other workspace is simply tax, in the line
// editor as much as in the ledger.

import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/core/currency.dart';
import 'package:nizkhata/widgets/txn_lines_editor.dart';

void main() {
  tearDown(() => MoneyContext.currency = 'INR');

  test('an INR workspace keeps "Tax / GST"', () {
    expect(lineTypeLabel('tax'), 'Tax / GST');
  });

  test('any other workspace says "Tax"', () {
    MoneyContext.currency = 'USD';
    expect(lineTypeLabel('tax'), 'Tax');
    expect(lineTypeLabel('expense'), 'Expense');
  });
}
