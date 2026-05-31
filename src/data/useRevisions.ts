// Load the revision history for a single entity, newest first. Used by detail
// modals to show "who changed what, when".
//
// Queries by workspaceId + entityId equality and sorts client-side. The
// workspaceId filter is REQUIRED: the security rule gates reads on
// isMember(resource.data.workspaceId), and Firestore rejects a query whose
// constraints don't guarantee every matching doc passes the rule ("rules are
// not filters") — filtering by entityId alone returned permission-denied, which
// the retry wrapper surfaced as "Couldn't load history" after a few retries.
// Two equality filters are served by single-field indexes; no composite needed.

import { useEffect, useState } from "react";
import { collection, query, where } from "firebase/firestore";
import { db } from "@/firebase/config";
import { subscribeWithRetry } from "@/lib/firestoreRetry";
import { toDate } from "@/lib/derive";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import type { Revision } from "@/types/models";

export function useRevisions(entityId: string | null) {
  const { activeWorkspaceId } = useWorkspace();
  const [revisions, setRevisions] = useState<Revision[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!entityId || !activeWorkspaceId) {
      setRevisions([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    const q = query(
      collection(db, "revisions"),
      where("workspaceId", "==", activeWorkspaceId),
      where("entityId", "==", entityId),
    );
    const unsub = subscribeWithRetry(
      q,
      (snap) => {
        const list = snap.docs.map((d) => d.data() as Revision);
        // newest first; `at` may be null on a pending local write
        list.sort((a, b) => {
          const ta = a.at ? toDate(a.at).getTime() : Date.now();
          const tb = b.at ? toDate(b.at).getTime() : Date.now();
          return tb - ta;
        });
        setRevisions(list);
        setLoading(false);
      },
      (e) => {
        setError(e.message);
        setLoading(false);
      },
    );
    return unsub;
  }, [entityId, activeWorkspaceId]);

  return { revisions, loading, error };
}
