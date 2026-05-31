// Workspace-wide activity feed, newest first. Reads the append-only `revisions`
// log (already written in every mutation's batch) filtered to one workspace.
//
// Uses a composite (workspaceId asc, at desc) index — declared in
// firestore.indexes.json — so the server returns the newest `max` entries
// directly, with a final client-side sort to keep pending local writes on top.

import { useEffect, useState } from "react";
import { collection, limit as fbLimit, orderBy, query, where } from "firebase/firestore";
import { db } from "@/firebase/config";
import { subscribeWithRetry } from "@/lib/firestoreRetry";
import { toDate } from "@/lib/derive";
import type { Revision } from "@/types/models";

export function useWorkspaceActivity(workspaceId: string | null, max = 200) {
  const [activity, setActivity] = useState<Revision[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!workspaceId) {
      setActivity([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    const q = query(
      collection(db, "revisions"),
      where("workspaceId", "==", workspaceId),
      orderBy("at", "desc"),
      fbLimit(max),
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
        setActivity(list);
        setLoading(false);
      },
      (e) => {
        setError(e.message);
        setLoading(false);
      },
    );
    return unsub;
  }, [workspaceId, max]);

  return { activity, loading, error };
}
