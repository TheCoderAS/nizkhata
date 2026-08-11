// Activity (§?) — ports src/pages/Activity.tsx. Chronological, human-readable
// view of the append-only revision log: who created/updated/deleted what, when.
// Grouped by day; entity names resolved from live data where possible, falling
// back to the revision snapshot for entities that have since been deleted.
//
// Known omission vs web: no infinite-scroll pagination — this keeps the single
// live limit(100) query. Older activity beyond the newest 100 isn't shown.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

// Per-entity-type display label + trailing icon (mirrors web ENTITY_META).
const _entityMeta = <String, ({String label, IconData icon})>{
  'transactions': (label: 'transaction', icon: Icons.swap_horiz),
  'accounts': (label: 'account', icon: Icons.account_balance_wallet_outlined),
  'categories': (label: 'category', icon: Icons.sell_outlined),
  'contacts': (label: 'contact', icon: Icons.people_outline),
  'debts': (label: 'debt', icon: Icons.volunteer_activism_outlined),
  'dues': (label: 'due', icon: Icons.event_outlined),
  'budgets': (label: 'budget', icon: Icons.track_changes_outlined),
};

const _verbs = <String, String>{
  'create': 'added',
  'update': 'updated',
  'delete': 'deleted',
};

const _actionIcons = <String, IconData>{
  'create': Icons.add,
  'update': Icons.edit,
  'delete': Icons.delete_outline,
};

const _weekdays = <String>[
  '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>().activeWorkspaceId;
    // Watch live data so revision entities resolve to current names.
    final data = context.watch<DataController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: ws == null
          ? const EmptyView(title: 'No activity yet', icon: Icons.history)
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('revisions')
                  .where('workspaceId', isEqualTo: ws)
                  .orderBy('at', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyView(
                    icon: Icons.error_outline,
                    title: "Couldn't load activity",
                    hint: '${snapshot.error}',
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const ListSkeleton();
                }
                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const EmptyView(title: 'No activity yet', icon: Icons.history);
                }

                // Group revisions by day, preserving the query's desc order.
                final groups = <({String label, List<Map<String, dynamic>> items})>[];
                final indexByKey = <String, int>{};
                for (final d in docs) {
                  final m = d.data() as Map<String, dynamic>;
                  final at = m['at'];
                  final date = at is Timestamp ? at.toDate() : DateTime.now();
                  final key = '${date.year}-${date.month}-${date.day}';
                  var gi = indexByKey[key];
                  if (gi == null) {
                    gi = groups.length;
                    indexByKey[key] = gi;
                    groups.add((
                      label: '${_weekdays[date.weekday]}, ${formatDate(date)}',
                      items: <Map<String, dynamic>>[],
                    ));
                  }
                  groups[gi].items.add(m);
                }

                final cs = Theme.of(context).colorScheme;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: Text(
                          g.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Card(
                        child: Column(
                          children: [
                            for (var i = 0; i < g.items.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              _RevisionTile(revision: g.items[i], data: data),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

class _RevisionTile extends StatelessWidget {
  final Map<String, dynamic> revision;
  final DataController data;
  const _RevisionTile({required this.revision, required this.data});

  @override
  Widget build(BuildContext context) {
    final m = revision;
    final action = (m['action'] ?? 'update') as String;
    final entityType = (m['entityType'] ?? 'item') as String;
    final entityId = (m['entityId'] ?? '') as String;
    final by = m['by'] is Map ? (m['by'] as Map)['name'] as String? : null;
    final at = m['at'];
    final when = at is Timestamp ? _relative(at.toDate()) : 'just now';
    final snapshot = m['snapshot'] is Map ? Map<String, dynamic>.from(m['snapshot'] as Map) : null;

    final meta = _entityMeta[entityType];
    final label = meta?.label ?? entityType;
    final name = _resolveName(entityType, entityId, snapshot);

    final changed = (m['changedFields'] is List)
        ? (m['changedFields'] as List).map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const <String>[];

    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(_actionIcons[action] ?? Icons.edit),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: by ?? 'Someone', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: ' ${_verbs[action] ?? action} $label'),
            if (name != null)
              TextSpan(
                text: " '$name'",
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            if (action == 'update' && changed.isNotEmpty)
              TextSpan(
                text: ' (${changed.join(', ')})',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
      subtitle: Text(when),
      trailing: Icon(meta?.icon ?? Icons.edit, size: 18, color: cs.onSurfaceVariant),
    );
  }

  // Resolve the entity's display name from live data, falling back to the
  // revision snapshot (for deleted entities). Returns null when only a generic
  // label is available (so the UI shows just the entity type).
  String? _resolveName(String entityType, String id, Map<String, dynamic>? snapshot) {
    String? snap() {
      if (snapshot == null) return null;
      for (final key in const ['name', 'title', 'description', 'note']) {
        final v = snapshot[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    switch (entityType) {
      case 'accounts':
        return data.accountsById[id]?.name ?? snap();
      case 'categories':
        return data.categoriesById[id]?.name ?? snap();
      case 'contacts':
        return data.contactsById[id]?.name ?? snap();
      case 'debts':
        final label = data.debtsById[id]?.label;
        return (label != null && label.isNotEmpty) ? label : snap();
      case 'budgets':
        final b = _firstById(data.budgets, id, (x) => x.id);
        final catId = b?.categoryId ?? snapshot?['categoryId'] as String?;
        if (catId != null) return data.categoriesById[catId]?.name;
        return snap();
      case 'dues':
        final d = _firstById(data.dues, id, (x) => x.id);
        final title = d?.title;
        return (title != null && title.isNotEmpty) ? title : snap();
      case 'transactions':
        final t = _firstById(data.transactions, id, (x) => x.id);
        final note = t?.note;
        return (note != null && note.isNotEmpty) ? note : snap();
      default:
        return snap();
    }
  }

  static T? _firstById<T>(Iterable<T> items, String id, String Function(T) idOf) {
    for (final e in items) {
      if (idOf(e) == id) return e;
    }
    return null;
  }

  static String _relative(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatDate(date);
  }
}
