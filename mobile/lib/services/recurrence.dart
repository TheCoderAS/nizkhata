// Recurrence engine — all client-side, no schedulers. Dues with a recurrence
// rule get their next instance created automatically (safe: dues are
// commitments, not money movements) with a DETERMINISTIC id so repeated runs
// on any device can never duplicate an instance. Recurring transactions are
// only ever SUGGESTED (via the dashboard attention strip); money records are
// never written without a tap.

import '../data/models.dart';

/// The next occurrence after [from] for a frequency, clamping month-length
/// overflow (Jan 31 + 1 month → Feb 28/29, and it stays a valid date).
DateTime nextOccurrence(DateTime from, String freq) {
  switch (freq) {
    case 'weekly':
      return from.add(const Duration(days: 7));
    case 'yearly':
      return _clampedDate(from.year + 1, from.month, from.day);
    case 'monthly':
    default:
      final month = from.month == 12 ? 1 : from.month + 1;
      final year = from.month == 12 ? from.year + 1 : from.year;
      return _clampedDate(year, month, from.day);
  }
}

DateTime _clampedDate(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > lastDay ? lastDay : day);
}

/// Deterministic id for a series instance: same on every device, every run.
String recurringDueId(String seriesId, DateTime occurrence) =>
    'rec_${seriesId}_${occurrence.year}'
    '${occurrence.month.toString().padLeft(2, '0')}'
    '${occurrence.day.toString().padLeft(2, '0')}';

/// A due instance the engine wants to create.
class DueInstance {
  final String id;
  final Due template;
  final DateTime dueDate;
  DueInstance(this.id, this.template, this.dueDate);
}

/// Which next instances are missing. A recurring due spawns its successor once
/// it is settled/cancelled OR its due date has passed ([now]); the successor
/// reuses the series' fields and carries the recurrence forward. Existing ids
/// (all loaded dues) make this idempotent.
List<DueInstance> missingDueInstances(List<Due> dues, DateTime now) {
  final existingIds = {for (final d in dues) d.id};
  final out = <DueInstance>[];
  for (final d in dues) {
    final freq = d.recurrence;
    if (freq == null || freq.isEmpty) continue;
    final done = d.status == 'settled' || d.status == 'cancelled';
    final past = d.dueDate.isBefore(DateTime(now.year, now.month, now.day));
    if (!done && !past) continue;
    final seriesId = d.recurrenceId ?? d.id;
    final next = nextOccurrence(d.dueDate, freq);
    final id = recurringDueId(seriesId, next);
    if (existingIds.contains(id)) continue;
    // Only the LATEST instance of a series spawns (otherwise editing an old
    // settled instance would refill the whole history).
    final isLatest = !dues.any((o) =>
        o.id != d.id &&
        (o.recurrenceId ?? o.id) == seriesId &&
        o.dueDate.isAfter(d.dueDate));
    if (!isLatest) continue;
    out.add(DueInstance(id, d, next));
  }
  return out;
}

/// A recurring transaction whose next occurrence has arrived — suggested in
/// the attention strip, created only on tap.
class TxnSuggestion {
  final Txn template;
  final DateTime nextDate;
  TxnSuggestion(this.template, this.nextDate);
}

List<TxnSuggestion> recurringTxnSuggestions(List<Txn> txns, DateTime now) {
  final out = <TxnSuggestion>[];
  // Group recurring transactions by a series key (note + account + amount
  // shape); the newest one in each series is the live template.
  final bySeries = <String, Txn>{};
  for (final t in txns) {
    if (t.recurrence == null || t.recurrence!.isEmpty) continue;
    final key = '${t.note ?? ''}|${t.accountId}|${t.recurrence}';
    final cur = bySeries[key];
    if (cur == null || t.date.isAfter(cur.date)) bySeries[key] = t;
  }
  final today = DateTime(now.year, now.month, now.day);
  for (final t in bySeries.values) {
    final next = nextOccurrence(t.date, t.recurrence!);
    if (!next.isAfter(today)) out.add(TxnSuggestion(t, next));
  }
  return out;
}
