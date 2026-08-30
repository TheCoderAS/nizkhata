import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/data/derive.dart';
import 'package:nizkhata/data/models.dart';
import 'package:nizkhata/widgets/txn_lines_editor.dart';

TxnLine _line(String id, String type, double amount, {String? toAccountId, String? debtId}) =>
    TxnLine(lineId: id, type: type, amount: amount, toAccountId: toAccountId, debtId: debtId);

Debt _debt(String id, String contactId, {String direction = 'owe', String? label}) => Debt(
      id: id,
      workspaceId: 'ws',
      contactId: contactId,
      direction: direction,
      purpose: 'loan',
      principal: 1000,
      status: 'open',
      label: label,
    );

void main() {
  group('transfers collapse to one authored line', () {
    test('a stored out/in pair reads as a single transfer', () {
      final drafts = draftsFromLines([
        _line('a', 'transfer_out', 5000),
        _line('b', 'transfer_in', 5000, toAccountId: 'acc2'),
      ]);
      expect(drafts.length, 1);
      expect(drafts.single.type, 'transfer_out');
      expect(drafts.single.amountValue, 5000);
      expect(drafts.single.toAccountId, 'acc2');
      // Both stored ids are kept so an edit rewrites the same pair.
      expect(drafts.single.lineId, 'a');
      expect(drafts.single.pairLineId, 'b');
    });

    test('expanding puts the pair back, ids and destination intact', () {
      final drafts = draftsFromLines([
        _line('a', 'transfer_out', 5000),
        _line('b', 'transfer_in', 5000, toAccountId: 'acc2'),
      ]);
      final maps = lineMapsFromDrafts(drafts, 111);
      expect(maps.length, 2);
      expect(maps[0]['lineId'], 'a');
      expect(maps[0]['type'], 'transfer_out');
      expect(maps[0].containsKey('toAccountId'), false); // the in-leg carries it
      expect(maps[1]['lineId'], 'b');
      expect(maps[1]['type'], 'transfer_in');
      expect(maps[1]['toAccountId'], 'acc2');
      expect(maps[1]['amount'], 5000);
    });

    test('a new transfer expands to a balancing pair', () {
      final d = LineDraft(type: 'transfer_out');
      d.amount.text = '250';
      d.toAccountId = 'acc2';
      final maps = lineMapsFromDrafts([d], 999);
      expect(maps.map((m) => m['type']), ['transfer_out', 'transfer_in']);
      expect(maps.every((m) => m['amount'] == 250), true);
      expect(maps[1]['toAccountId'], 'acc2');
    });

    test('two transfers pair up in order rather than crossing over', () {
      final drafts = draftsFromLines([
        _line('o1', 'transfer_out', 100),
        _line('o2', 'transfer_out', 200),
        _line('i1', 'transfer_in', 100, toAccountId: 'accA'),
        _line('i2', 'transfer_in', 200, toAccountId: 'accB'),
      ]);
      expect(drafts.length, 2);
      expect(drafts[0].toAccountId, 'accA');
      expect(drafts[0].amountValue, 100);
      expect(drafts[1].toAccountId, 'accB');
      expect(drafts[1].amountValue, 200);
    });

    test('an unpaired leg stays its own editable line', () {
      final drafts = draftsFromLines([_line('x', 'transfer_in', 75, toAccountId: 'accA')]);
      expect(drafts.length, 1);
      expect(drafts.single.type, 'transfer_in');
      expect(drafts.single.toAccountId, 'accA');
    });

    test('a transfer moves money out of the source account exactly once', () {
      final d = LineDraft(type: 'transfer_out');
      d.amount.text = '5000';
      d.toAccountId = 'acc2';
      expect(computeTotal(txnLinesFromDrafts([d]), const {}), -5000);
      expect(draftSignedAmount(d, const {}), -5000);
    });

    test('other line types are untouched by the round trip', () {
      final drafts = draftsFromLines([
        _line('e1', 'expense', 300),
        _line('i1', 'income', 900),
      ]);
      expect(drafts.map((d) => d.type), ['expense', 'income']);
      expect(lineMapsFromDrafts(drafts, 5).length, 2);
    });
  });

  group('debts offered to a line', () {
    final debts = [
      _debt('d2', 'c1', label: 'Zoya loan'),
      _debt('d1', 'c1', label: 'Amit loan'),
      _debt('d3', 'c2', label: 'Someone else'),
      Debt(
          id: 'shared1',
          workspaceId: 'ws',
          contactId: 'c1',
          direction: 'owe',
          purpose: 'shared',
          principal: 10,
          status: 'open',
          label: 'Shared trip'),
    ];

    test('only the chosen contact, name-sorted, no shared-ledger debts', () {
      final got = debtsForContact(debts, 'c1', const {});
      expect(got.map((d) => d.id), ['d1', 'd2']);
    });

    test('nothing to choose from until a contact is picked', () {
      expect(debtsForContact(debts, null, const {}), isEmpty);
    });
  });

  group('per-line validation', () {
    test('a transfer needs a destination that is not the source', () {
      final d = LineDraft(type: 'transfer_out');
      d.amount.text = '100';
      expect(validateLineDraft(d, accountId: 'acc1'),
          contains('Choose the account the money moves to.'));

      d.toAccountId = 'acc1';
      expect(validateLineDraft(d, accountId: 'acc1'),
          contains('The destination must differ from the account above.'));

      d.toAccountId = 'acc2';
      expect(validateLineDraft(d, accountId: 'acc1'), isEmpty);
    });

    test('a debt line needs a contact first, then one of their debts', () {
      final d = LineDraft(type: 'repayment');
      d.amount.text = '500';
      expect(validateLineDraft(d, accountId: 'acc1').first,
          'Pick a contact on the transaction before linking a debt.');

      expect(validateLineDraft(d, accountId: 'acc1', contactId: 'c1').first,
          'Link the debt this line settles.');

      d.debtId = 'd9';
      final byId = {'d9': _debt('d9', 'c2')};
      expect(validateLineDraft(d, accountId: 'acc1', contactId: 'c1', debtsById: byId).first,
          contains('belongs to someone else'));

      expect(
          validateLineDraft(d, accountId: 'acc1', contactId: 'c2', debtsById: byId), isEmpty);
    });

    test('an amount is always required', () {
      final d = LineDraft(type: 'expense');
      expect(validateLineDraft(d), contains('Enter an amount greater than 0.'));
      d.amount.text = '10';
      expect(validateLineDraft(d, accountId: 'acc1'), isEmpty);
    });

    test('form-level errors are numbered per line', () {
      final a = LineDraft(type: 'expense')..amount.text = '10';
      final b = LineDraft(type: 'expense');
      final errs = validateLineDrafts([a, b], accountId: 'acc1');
      expect(errs.any((e) => e.startsWith('Line 2:')), true);
      expect(errs.any((e) => e.startsWith('Line 1:')), false);
    });

    test('authored transfers never trip the balance rule', () {
      final d = LineDraft(type: 'transfer_out')
        ..amount.text = '400'
        ..toAccountId = 'acc2';
      expect(validateLineDrafts([d], accountId: 'acc1'), isEmpty);
    });
  });

  group('draft copy and write-back', () {
    test('editing a copy leaves the original alone until applied', () {
      final original = LineDraft(type: 'expense')
        ..amount.text = '100'
        ..categoryId = 'cat1';
      final copy = original.copy()
        ..amount.text = '250'
        ..categoryId = 'cat2';

      expect(original.amount.text, '100');
      expect(original.categoryId, 'cat1');

      original.applyFrom(copy);
      expect(original.amount.text, '250');
      expect(original.categoryId, 'cat2');
    });

    test('a copy carries the stored ids so edits rewrite in place', () {
      final original = LineDraft(type: 'transfer_out', lineId: 'a', pairLineId: 'b');
      final copy = original.copy();
      expect(copy.lineId, 'a');
      expect(copy.pairLineId, 'b');
    });
  });
}
