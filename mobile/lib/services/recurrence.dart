// Recurrence engine — all client-side, no schedulers. Dues with a recurrence
// rule get their next instance created automatically (safe: dues are
// commitments, not money movements) with a DETERMINISTIC id so repeated runs
// on any device can never duplicate an instance. Recurring transactions are
// only ever SUGGESTED (via the dashboard attention strip); money records are
// never written without a tap.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/models.dart';
import 'title_tokens.dart';

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

/// The Firestore document for a spawned instance.
///
/// Everything but the date is inherited from the template, with one exception:
/// title and note are RE-RENDERED from their patterns for this occurrence.
/// That is the whole point of patterns — copying "RD Payment - Aug" forward
/// would stamp August on every month forever. A template with no pattern is
/// copied verbatim, exactly as before.
Map<String, dynamic> nextDueDoc(DueInstance inst, {int fyStartMonth = 4}) {
  final t = inst.template;
  final occurrence = t.occurrence + 1;
  String? render(String? pattern, String? fallback) {
    if (pattern == null) return fallback;
    return renderTokens(pattern, inst.dueDate,
        occurrence: occurrence, fyStartMonth: fyStartMonth);
  }

  return {
    'direction': t.direction,
    'title': render(t.titlePattern, t.title) ?? '',
    'amount': t.amount,
    'dueDate': Timestamp.fromDate(inst.dueDate),
    'contactId': t.contactId,
    'accountId': t.accountId,
    'categoryId': t.categoryId,
    'note': render(t.notePattern, t.note),
    'lines': [for (final l in t.lines) l.toMap()],
    'recurrence': t.recurrence,
    'recurrenceId': t.recurrenceId ?? t.id,
    // Carried forward so the instance after this one renders from the same
    // pattern rather than from the text this one happened to produce.
    'titlePattern': t.titlePattern,
    'notePattern': t.notePattern,
    'occurrence': occurrence,
  };
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
  // shape); the newest one in each series is the live template. The key uses
  // the note PATTERN where there is one: a note that renders the month would
  // otherwise give every occurrence its own series, and each of them would
  // suggest a successor.
  final bySeries = <String, Txn>{};
  for (final t in txns) {
    if (t.recurrence == null || t.recurrence!.isEmpty) continue;
    final key = '${t.notePattern ?? t.note ?? ''}|${t.accountId}|${t.recurrence}';
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
