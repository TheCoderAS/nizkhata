// Category memory for statement import — derived, never stored. The user's
// existing categorized transactions ARE the training data: at review time we
// index their notes by distinctive tokens and suggest a category for each new
// statement row by token overlap. Zero storage, zero infra; because it reads
// workspace transactions, learning is shared across members and devices for
// free, and correcting a category on any past transaction "re-trains" it.

import '../data/models.dart';

/// Words that carry no merchant identity in bank narrations.
const _noise = <String>{
  'upi', 'neft', 'imps', 'rtgs', 'ach', 'nach', 'pos', 'atm', 'wdl', 'txn',
  'ref', 'pay', 'payment', 'paid', 'transfer', 'trf', 'credit', 'debit',
  'the', 'and', 'for', 'from', 'ltd', 'pvt', 'llp', 'india', 'bank',
};

/// Tokenize a narration: lowercase alphanumeric runs, minus pure numbers,
/// short fragments and boilerplate words.
Set<String> narrationTokens(String text) {
  final out = <String>{};
  for (final m in RegExp(r'[a-zA-Z0-9]+').allMatches(text.toLowerCase())) {
    final t = m.group(0)!;
    if (t.length < 3) continue;
    if (RegExp(r'^\d+$').hasMatch(t)) continue;
    if (_noise.contains(t)) continue;
    out.add(t);
  }
  return out;
}

class _Memory {
  final Set<String> tokens;
  final String categoryId;
  final DateTime date;
  _Memory(this.tokens, this.categoryId, this.date);
}

/// Suggests categories for statement rows from past categorized transactions.
class CategoryMemory {
  final List<_Memory> _entries = [];

  /// Index the most recent [cap] transactions that have a note and a
  /// categorized line (the first categorized line's category represents the
  /// transaction — imports create single-line transactions anyway).
  CategoryMemory.fromTransactions(Iterable<Txn> txns, {int cap = 1500}) {
    final sorted = [...txns]..sort((a, b) => b.date.compareTo(a.date));
    for (final t in sorted) {
      if (_entries.length >= cap) break;
      final note = t.note;
      if (note == null || note.trim().isEmpty) continue;
      String? categoryId;
      for (final l in t.lines) {
        if (l.categoryId != null && (l.type == 'expense' || l.type == 'income')) {
          categoryId = l.categoryId;
          break;
        }
      }
      if (categoryId == null) continue;
      final tokens = narrationTokens(note);
      if (tokens.isEmpty) continue;
      _entries.add(_Memory(tokens, categoryId, t.date));
    }
  }

  bool get isEmpty => _entries.isEmpty;

  /// Best category for [description], or null when nothing matches with
  /// confidence. Score = total length of shared tokens (longer shared words
  /// are stronger evidence); ties break toward the most recent transaction.
  String? suggest(String description) {
    final tokens = narrationTokens(description);
    if (tokens.isEmpty) return null;
    String? best;
    var bestScore = 0;
    DateTime? bestDate;
    for (final e in _entries) {
      var score = 0;
      for (final t in tokens) {
        if (e.tokens.contains(t)) score += t.length;
      }
      if (score == 0) continue;
      if (score > bestScore || (score == bestScore && (bestDate == null || e.date.isAfter(bestDate)))) {
        bestScore = score;
        best = e.categoryId;
        bestDate = e.date;
      }
    }
    // Require at least one solid shared token (≥4 chars' worth of overlap) so
    // a stray 3-letter fragment can't mislabel a row.
    return bestScore >= 4 ? best : null;
  }
}
