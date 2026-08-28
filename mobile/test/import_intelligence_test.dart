import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/data/due_settlement.dart';
import 'package:nizkhata/data/models.dart';
import 'package:nizkhata/services/import_learning.dart';
import 'package:nizkhata/services/statement_parser.dart';

Txn _txn(String note, String categoryId, DateTime date, {String type = 'expense'}) => Txn(
      id: 't_${note.hashCode}_${date.microsecondsSinceEpoch}',
      workspaceId: 'ws',
      date: date,
      accountId: 'acc',
      totalAmount: type == 'expense' ? -100 : 100,
      hasSplit: false,
      financialYear: '2025-26',
      lines: [TxnLine(lineId: 'l0', type: type, amount: 100, categoryId: categoryId)],
      note: note,
    );

void main() {
  group('narrationTokens', () {
    test('keeps merchant identity, drops boilerplate and numbers', () {
      expect(narrationTokens('UPI-GROCERYMART-PAY 509912345678'), {'grocerymart'});
      expect(narrationTokens('NEFT SALARY CREDIT ACME CORP'), {'salary', 'acme', 'corp'});
      expect(narrationTokens('123 456'), isEmpty);
    });
  });

  group('CategoryMemory', () {
    final memory = CategoryMemory.fromTransactions([
      _txn('UPI-GROCERYMART-PAY 111', 'cat_groceries', DateTime(2025, 3, 1)),
      _txn('SWIGGY ORDER 222', 'cat_food', DateTime(2025, 3, 5)),
      _txn('NEFT SALARY ACME CORP', 'cat_salary', DateTime(2025, 3, 31), type: 'income'),
      // Older conflicting mapping for the same merchant — recency should win.
      _txn('UPI-GROCERYMART-PAY 000', 'cat_misc', DateTime(2024, 1, 1)),
    ]);

    test('suggests by merchant token, most recent mapping wins', () {
      expect(memory.suggest('UPI-GROCERYMART-PAY 999888'), 'cat_groceries');
      expect(memory.suggest('SWIGGY ORDER 987'), 'cat_food');
      expect(memory.suggest('SALARY ACME CORP MAR'), 'cat_salary');
    });

    test('no confident match → null', () {
      expect(memory.suggest('POS 445566 XYZ'), isNull);
      expect(memory.suggest(''), isNull);
    });

    test('transactions without notes or categories are ignored', () {
      final m = CategoryMemory.fromTransactions([
        Txn(
          id: 'x',
          workspaceId: 'ws',
          date: DateTime(2025, 1, 1),
          accountId: 'a',
          totalAmount: -5,
          hasSplit: false,
          financialYear: '2024-25',
          lines: [TxnLine(lineId: 'l', type: 'expense', amount: 5)],
        ),
      ]);
      expect(m.isEmpty, true);
    });
  });

  group('balance column', () {
    test('suggestMapping finds balance and keeps it away from amounts', () {
      final m = suggestMapping(['Date', 'Narration', 'Withdrawal', 'Deposit', 'Closing Balance']);
      expect(m.balance, 4);
      expect(m.debit, 2);
      expect(m.credit, 3);
      expect(m.amount, isNull);
    });

    test('drafts carry the running balance, incl. from continuation lines', () {
      final g = StatementGrid(kind: StatementKind.csv, headerRow: 0, rows: [
        ['Date', 'Narration', 'Withdrawal', 'Deposit', 'Balance'],
        ['01/04/2025', 'UPI-GROCERY', '450.00', '', '99,550.00'],
        ['02/04/2025', 'SALARY', '', '50,000.00', ''],
        ['', 'ACME CORP', '', '', '1,49,550.00'], // balance wrapped to line 2
      ]);
      final rows = buildImportRows(g, suggestMapping(g.header), DateOrder.dmy);
      expect(rows.length, 2);
      expect(rows[0].balance, 99550.00);
      expect(rows[1].balance, 149550.00);
    });
  });

  group('buildDueSettlement', () {
    test('scales multi-line dues (and TDS) for partial payments', () {
      final due = Due(
        id: 'd1',
        workspaceId: 'ws',
        direction: 'payable',
        title: 'Contractor bill',
        amount: 1000,
        dueDate: DateTime(2025, 4, 10),
        status: 'open',
        lines: [
          TxnLine(lineId: 'a', type: 'expense', amount: 800, categoryId: 'cat_work'),
          TxnLine(
              lineId: 'b',
              type: 'expense',
              amount: 200,
              tax: {'taxable': true, 'head': 'services', 'tdsAmount': 20.0}),
        ],
      );
      final draft = buildDueSettlement(due, 500, {}, lineIdSeed: 42);
      expect(draft.lines.length, 2);
      expect(draft.lines[0]['amount'], 400.0);
      expect(draft.lines[1]['amount'], 100.0);
      expect((draft.lines[1]['tax'] as Map)['tdsAmount'], 10.0);
      expect(draft.signedTotal, -500.0);
    });

    test('legacy due without lines produces one typed line', () {
      final due = Due(
        id: 'd2',
        workspaceId: 'ws',
        direction: 'receivable',
        title: 'Rent',
        amount: 18000,
        dueDate: DateTime(2025, 4, 5),
        status: 'open',
        categoryId: 'cat_rent',
      );
      final draft = buildDueSettlement(due, 18000, {}, lineIdSeed: 7);
      expect(draft.lines.single['type'], 'income');
      expect(draft.lines.single['categoryId'], 'cat_rent');
      expect(draft.signedTotal, 18000.0);
    });
  });
}
