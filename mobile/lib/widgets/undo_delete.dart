import 'package:flutter/material.dart';

import '../data/mutations.dart';

/// Delete an entity with a 6-second Undo window: the document's data is
/// captured before deletion and restored under the same id on Undo (links from
/// other documents keep working because the id is unchanged).
Future<void> deleteWithUndo(
  BuildContext context, {
  required Actor actor,
  required String collection,
  required String workspaceId,
  required String id,
  required String label,
}) async {
  final m = Mutations(actor);
  final snapshot = await m.deleteWithSnapshot(collection, workspaceId, id);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('$label deleted'),
    duration: const Duration(seconds: 6),
    // Flutter defaults `persist` to `action != null`, so the moment this bar
    // gained an Undo button it stopped ever timing out: it sat on screen until
    // something else replaced it. The duration above was being ignored.
    persist: false,
    // And a bar that can linger needs a way out that is not a guessed swipe.
    showCloseIcon: true,
    action: snapshot == null
        ? null
        : SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await m.restoreEntity(collection, workspaceId, id, snapshot);
              } catch (_) {
                // Restoring can fail if permissions changed mid-flight; the
                // snackbar is gone by then, so fail quietly.
              }
            },
          ),
  ));
}
