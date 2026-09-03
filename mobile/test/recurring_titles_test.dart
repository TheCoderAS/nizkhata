import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nizkhata/data/models.dart';
import 'package:nizkhata/services/recurrence.dart';

Due _due({
  String id = 'd1',
  String title = 'RD Payment - Aug',
  String? titlePattern,
  String? note,
  String? notePattern,
  int occurrence = 1,
  DateTime? dueDate,
  String status = 'settled',
  String? recurrenceId,
}) =>
    Due(
      id: id,
      workspaceId: 'ws',
      direction: 'payable',
      title: title,
      titlePattern: titlePattern,
      note: note,
      notePattern: notePattern,
      occurrence: occurrence,
      amount: 5000,
      dueDate: dueDate ?? DateTime(2026, 8, 5),
      status: status,
      recurrence: 'monthly',
      recurrenceId: recurrenceId,
    );

Txn _txn({
  required String id,
  required DateTime date,
  String? note,
  String? notePattern,
}) =>
    Txn(
      id: id,
      workspaceId: 'ws',
      date: date,
      accountId: 'a1',
      totalAmount: 1200,
      hasSplit: false,
      financialYear: '2026-27',
      note: note,
      notePattern: notePattern,
      recurrence: 'monthly',
      lines: [TxnLine(lineId: 'l1', type: 'expense', amount: 1200)],
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN', null);
  });

  final now = DateTime(2026, 9, 20);

  group('spawned due instances', () {
    test('a pattern is re-rendered for the new month, not copied', () {
      final inst = missingDueInstances([
        _due(title: 'RD Payment - Aug', titlePattern: 'RD Payment - {MMM}'),
      ], now)
          .single;
      final doc = nextDueDoc(inst);
      expect(inst.dueDate, DateTime(2026, 9, 5));
      expect(doc['title'], 'RD Payment - Sept');
    });

    test('a plain title is still copied verbatim', () {
      final inst = missingDueInstances([_due(title: 'Rent')], now).single;
      expect(nextDueDoc(inst)['title'], 'Rent');
      expect(nextDueDoc(inst)['titlePattern'], isNull);
    });

    test('the pattern travels to the next instance', () {
      final first = _due(titlePattern: 'RD Payment - {MMM}');
      final doc = nextDueDoc(missingDueInstances([first], now).single);
      expect(doc['titlePattern'], 'RD Payment - {MMM}');

      // Feed that instance back in as the template, as a later sync would.
      final second = _due(
        id: doc['recurrenceId'] == null ? 'd2' : 'd2',
        title: doc['title'] as String,
        titlePattern: doc['titlePattern'] as String?,
        occurrence: doc['occurrence'] as int,
        dueDate: (doc['dueDate'] as Timestamp).toDate(),
        recurrenceId: doc['recurrenceId'] as String?,
      );
      final third = nextDueDoc(missingDueInstances([second], DateTime(2026, 10, 20)).single);
      expect(third['title'], 'RD Payment - Oct');
    });

    test('notes are rendered too', () {
      final inst = missingDueInstances([
        _due(note: 'Instalment 1', notePattern: 'Instalment {#}'),
      ], now)
          .single;
      expect(nextDueDoc(inst)['note'], 'Instalment 2');
    });

    test('{#} counts occurrences up the series', () {
      final inst = missingDueInstances([_due(titlePattern: 'EMI {#} of 24', occurrence: 6)], now).single;
      final doc = nextDueDoc(inst);
      expect(doc['title'], 'EMI 7 of 24');
      expect(doc['occurrence'], 7);
    });

    test('{FY} follows the workspace financial year', () {
      // A March due spawning into April crosses into the next FY.
      final inst = missingDueInstances([
        _due(titlePattern: 'Advance tax {FY}', dueDate: DateTime(2026, 3, 15)),
      ], DateTime(2026, 4, 20))
          .single;
      expect(nextDueDoc(inst, fyStartMonth: 4)['title'], 'Advance tax 2026-27');
      expect(nextDueDoc(inst, fyStartMonth: 1)['title'], 'Advance tax 2026');
    });

    test('everything else is inherited unchanged', () {
      final inst = missingDueInstances([_due(titlePattern: 'RD - {MMM}')], now).single;
      final doc = nextDueDoc(inst);
      expect(doc['amount'], 5000);
      expect(doc['direction'], 'payable');
      expect(doc['recurrence'], 'monthly');
      expect(doc['recurrenceId'], 'd1');
      expect((doc['lines'] as List), isEmpty);
    });
  });

  group('recurring transaction suggestions', () {
    test('a rendered note does not split one series into many', () {
      // Three months of the same series, each with its own rendered note.
      final txns = [
        for (final m in [6, 7, 8])
          _txn(
            id: 't$m',
            date: DateTime(2026, m, 3),
            note: 'Broadband ${['Jun', 'Jul', 'Aug'][m - 6]}',
            notePattern: 'Broadband {MMM}',
          ),
      ];
      final suggestions = recurringTxnSuggestions(txns, now);
      // One series, so one suggestion — for the month after the latest.
      expect(suggestions.length, 1);
      expect(suggestions.single.nextDate, DateTime(2026, 9, 3));
      expect(suggestions.single.template.id, 't8');
    });

    test('transactions without patterns group as they always did', () {
      final txns = [
        _txn(id: 't1', date: DateTime(2026, 7, 3), note: 'Broadband'),
        _txn(id: 't2', date: DateTime(2026, 8, 3), note: 'Broadband'),
      ];
      expect(recurringTxnSuggestions(txns, now).length, 1);
      // Genuinely different notes are still genuinely different series.
      final mixed = [
        _txn(id: 't1', date: DateTime(2026, 8, 3), note: 'Broadband'),
        _txn(id: 't2', date: DateTime(2026, 8, 3), note: 'Gym'),
      ];
      expect(recurringTxnSuggestions(mixed, now).length, 2);
    });
  });
}
