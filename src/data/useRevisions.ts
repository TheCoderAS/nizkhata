// Load the revision history for a single entity, newest first. Used by detail
// modals to show "who changed what, when".
//
// Queries on `entityId` equality only (single-field, auto-indexed) and sorts
// client-side — avoids requiring a composite (entityId + at) index to exist,
// which otherwise made history silently fail with "no history recorded".

import { useEffect, useState } from "react";
import { collection, query, where } from "firebase/firestore";
import { db } from "@/firebase/config";
import { subscribeWithRetry } from "@/lib/firestoreRetry";
import { toDate } from "@/lib/derive";
import type { Revision } from "@/types/models";

export function useRevisions(entityId: string | null) {
  const [revisions, setRevisions] = useState<Revision[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!entityId) {
      setRevisions([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    setError(null);
    const q = query(
      collection(db, "revisions"),
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
  }, [entityId]);

  return { revisions, loading, error };
}
