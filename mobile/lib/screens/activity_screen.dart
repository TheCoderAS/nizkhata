import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  static const _verbs = <String, String>{
    'create': 'added',
    'update': 'updated',
    'delete': 'deleted',
  };

  static const _icons = <String, IconData>{
    'create': Icons.add,
    'update': Icons.edit,
    'delete': Icons.delete,
  };

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>().activeWorkspaceId;

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: ws == null
          ? const EmptyView(title: 'No activity yet')
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('revisions')
                  .where('workspaceId', isEqualTo: ws)
                  .orderBy('at', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingView();
                }
                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const EmptyView(title: 'No activity yet');
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final m = docs[i].data() as Map<String, dynamic>;
                    final action = (m['action'] ?? 'update') as String;
                    final entityType = (m['entityType'] ?? 'item') as String;
                    final by = m['by'] is Map ? (m['by'] as Map)['name'] as String? : null;
                    final at = m['at'];
                    final when = at is Timestamp ? _relative(at.toDate()) : 'just now';
                    return ListTile(
                      leading: Icon(_icons[action] ?? Icons.edit),
                      title: Text(
                        '${by ?? 'Someone'} ${_verbs[action] ?? action} ${_singularize(entityType)}',
                      ),
                      subtitle: Text(when),
                    );
                  },
                );
              },
            ),
    );
  }

  static String _singularize(String entityType) {
    if (entityType.length > 3 && entityType.endsWith('ies')) {
      return '${entityType.substring(0, entityType.length - 3)}y';
    }
    if (entityType.endsWith('s')) {
      return entityType.substring(0, entityType.length - 1);
    }
    return entityType;
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
