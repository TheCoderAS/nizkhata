// Load the revision history for a single entity, newest first. Used by detail
// modals to show "who changed what, when".

import { useEffect, useState } from "react";
import { collection, orderBy, query, where } from "firebase/firestore";
import { db } from "@/firebase/config";
import { subscribeWithRetry } from "@/lib/firestoreRetry";
import type { Revision } from "@/types/models";

export function useRevisions(entityId: string | null) {
  const [revisions, setRevisions] = useState<Revision[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!entityId) {
      setRevisions([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    const q = query(
      collection(db, "revisions"),
      where("entityId", "==", entityId),
      orderBy("at", "desc"),
    );
    const unsub = subscribeWithRetry(
      q,
      (snap) => {
        setRevisions(snap.docs.map((d) => d.data() as Revision));
        setLoading(false);
      },
      () => setLoading(false),
    );
    return unsub;
  }, [entityId]);

  return { revisions, loading };
}
