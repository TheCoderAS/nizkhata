import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../services/import_learning.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

/// Bulk categorisation — uncategorised transactions (mostly from statement
/// imports) grouped by merchant signature so a whole month of "SWIGGY…" rows
/// gets one tap. Each pass also trains future import suggestions, since the
/// learning engine reads categorised history.
class CategorizeScreen extends StatefulWidget {
  const CategorizeScreen({super.key});

  @override
  State<CategorizeScreen> createState() => _CategorizeScreenState();
}

class _Group {
  final String key;
  final String sample; // representative note
  final List<Txn> txns;
  String? categoryId; // chosen (prefilled from learning when confident)
  bool suggested = false;
  _Group(this.key, this.sample, this.txns);
  double get total => txns.fold(0.0, (s, t) => s + t.totalAmount);
}

class _CategorizeScreenState extends State<CategorizeScreen> {
  final Set<String> _busyGroups = {};
  // Explicit user picks, keyed by group signature — groups are rebuilt on
  // every data change, so choices must live outside them.
  final Map<String, String?> _chosen = {};

  bool _isUncategorized(Txn t) => t.lines
      .any((l) => (l.type == 'expense' || l.type == 'income') && l.categoryId == null);

  List<_Group> _buildGroups(DataController data) {
    final uncategorized = data.transactions.where(_isUncategorized).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final byKey = <String, _Group>{};
    for (final t in uncategorized) {
      final note = t.note ?? '';
      final tokens = narrationTokens(note).toList()..sort();
      final key = tokens.isEmpty ? '(no description)' : tokens.join(' ');
      (byKey[key] ??= _Group(key, note.isEmpty ? '(no description)' : note, []))
          .txns
          .add(t);
    }
    final groups = byKey.values.toList()
      ..sort((a, b) => b.txns.length.compareTo(a.txns.length));
    // Prefill from the learning engine when it has a confident match.
    final memory = CategoryMemory.fromTransactions(data.transactions);
    final catsById = {for (final c in data.categories) c.id: c};
    for (final g in groups) {
      if (memory.isEmpty) break;
      final s = memory.suggest(g.sample);
      if (s == null) continue;
      final kind = catsById[s]?.kind;
      final wantKind = g.total < 0 ? 'expense' : 'income';
      if (kind == wantKind) {
        g.categoryId = s;
        g.suggested = true;
      }
    }
    for (final g in groups) {
      if (_chosen.containsKey(g.key)) {
        g.categoryId = _chosen[g.key];
        g.suggested = false;
      }
    }
    return groups;
  }

  Future<void> _apply(_Group g) async {
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    final user = context.read<AuthController>().user;
    final categoryId = g.categoryId;
    if (ws == null || user == null || categoryId == null) return;
    setState(() => _busyGroups.add(g.key));
    try {
      await Mutations(Actor.fromUser(user)).bulkSetTxnCategory(ws, g.txns, categoryId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${g.txns.length} transaction'
                '${g.txns.length == 1 ? '' : 's'} categorised')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyGroups.remove(g.key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canEdit = ws.can('transactions.edit');
    final groups = _buildGroups(data);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Categorise transactions')),
      body: !canEdit
          ? const Center(child: Text("Your role doesn't allow editing transactions."))
          : groups.isEmpty
              ? const EmptyView(
                  icon: Icons.task_alt,
                  title: 'All caught up',
                  hint: 'Every transaction has a category.')
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final g = groups[i];
                    final cats = (g.total < 0
                        ? data.categories.where((c) => c.kind == 'expense')
                        : data.categories.where((c) => c.kind == 'income'))
                        .toList()
                      ..sort((a, b) => a.name.compareTo(b.name));
                    final valid = cats.any((c) => c.id == g.categoryId) ? g.categoryId : null;
                    final busy = _busyGroups.contains(g.key);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(g.sample,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 8),
                              Text(formatMoney(g.total, currency),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: g.total < 0 ? cs.error : cs.primary)),
                            ],
                          ),
                          Text(
                              '${g.txns.length} transaction${g.txns.length == 1 ? '' : 's'}'
                              '${g.suggested ? ' · suggested from your history' : ''}',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: valid,
                                  isExpanded: true,
                                  isDense: true,
                                  decoration:
                                      const InputDecoration(labelText: 'Category', isDense: true),
                                  items: [
                                    for (final c in cats)
                                      DropdownMenuItem(
                                          value: c.id,
                                          child: Text(c.name, overflow: TextOverflow.ellipsis)),
                                  ],
                                  onChanged: (v) => setState(() {
                                    _chosen[g.key] = v;
                                    g.categoryId = v;
                                    g.suggested = false;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: busy || g.categoryId == null ? null : () => _apply(g),
                                child: busy
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Text('Apply'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
