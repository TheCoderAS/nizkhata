// Per-entity audit footer + collapsible revision timeline.
// Ports the web DetailDialog audit footer + RevisionHistory timeline: reads the
// append-only `revisions` collection for one entity (created/updated/deleted,
// by whom, when) and renders it inside any detail sheet.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class _Rev {
  final String action;
  final String byName;
  final DateTime? at;
  final List<String> changedFields;
  _Rev({required this.action, required this.byName, this.at, required this.changedFields});

  static _Rev fromDoc(Map<String, dynamic> m) {
    final by = (m['by'] as Map?)?.cast<String, dynamic>();
    final ts = m['at'];
    return _Rev(
      action: (m['action'] ?? '') as String,
      byName: (by?['name'] ?? 'Unknown') as String,
      at: ts is Timestamp ? ts.toDate() : null,
      changedFields: ((m['changedFields'] as List?)?.cast<String>()) ?? const [],
    );
  }
}

/// Shows "Added by … · Last edited by …" plus an expandable revision list for
/// the given [entityType]/[entityId]. Queries by entityId only (single-field
/// index, no composite index needed) and filters/sorts client-side.
class RevisionHistory extends StatelessWidget {
  final String entityType;
  final String entityId;
  const RevisionHistory({super.key, required this.entityType, required this.entityId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('revisions')
          .where('entityId', isEqualTo: entityId)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        final revs = snap.data!.docs.map((d) => _Rev.fromDoc(d.data())).toList()
          ..sort((a, b) => (a.at ?? DateTime(0)).compareTo(b.at ?? DateTime(0)));

        final created = revs.firstWhere((r) => r.action == 'create', orElse: () => revs.first);
        final last = revs.last;

        String when(DateTime? d) {
          if (d == null) return '';
          final now = DateTime.now();
          final local = d.toLocal();
          final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
          final hh = local.hour.toString().padLeft(2, '0');
          final mm = local.minute.toString().padLeft(2, '0');
          if (sameDay) return 'today $hh:$mm';
          return '${local.day}/${local.month}/${local.year} $hh:$mm';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Added by ${created.byName}${created.at != null ? ' · ${when(created.at)}' : ''}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            if (last.action != 'create' || last != created)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Last edited by ${last.byName}${last.at != null ? ' · ${when(last.at)}' : ''}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
            if (revs.length > 1)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  visualDensity: VisualDensity.compact,
                  title: Text('View history (${revs.length})',
                      style: TextStyle(fontSize: 13, color: cs.primary, fontWeight: FontWeight.w600)),
                  children: [
                    for (final r in revs.reversed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 4, right: 10),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: r.action == 'create'
                                    ? cs.primary
                                    : (r.action == 'delete' ? cs.error : cs.secondary),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_actionLabel(r.action)} · ${r.byName}',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    '${when(r.at)}'
                                    '${r.changedFields.isNotEmpty ? ' — ${r.changedFields.join(', ')}' : ''}',
                                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  static String _actionLabel(String a) =>
      a == 'create' ? 'Created' : (a == 'update' ? 'Edited' : (a == 'delete' ? 'Deleted' : a));
}
