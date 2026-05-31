// Live + paginated subscription to the workspace revision log (the Activity
// feed). Kept out of WorkspaceDataProvider because it can grow large and only
// the Activity screen needs it.
//
// Strategy (agreed): the first page (newest 20) stays real-time via
// onSnapshot; older pages are fetched one page at a time with a cursor
// (getDocs + startAfter). Everything is accumulated into a Map keyed by
// revision id — since revisions are append-only (never edited/deleted), this is
// gap-free: new live entries are just upserted at the top and previously loaded
// pages are never dropped.

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  collection,
  getDocs,
  limit,
  onSnapshot,
  orderBy,
  query,
  startAfter,
  where,
  type QueryDocumentSnapshot,
} from "firebase/firestore";
import { db } from "@/firebase/config";
import { toDate } from "@/lib/derive";
import type { Revision } from "@/types/models";

export const ACTIVITY_PAGE_SIZE = 20;

export interface WorkspaceActivity {
  activity: Revision[];
  loading: boolean; // initial first-page load
  loadingMore: boolean; // a "load older" fetch is in flight
  hasMore: boolean; // there may be older pages to fetch
  loadMore: () => void;
  error: string | null;
}

export function useWorkspaceActivity(workspaceId: string | null): WorkspaceActivity {
  const [byId, setById] = useState<Map<string, Revision>>(new Map());
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Cursors (DocumentSnapshots) for pagination. `liveLast` is the last doc of
  // the real-time first page; `olderLast` advances as we page backwards.
  const liveLast = useRef<QueryDocumentSnapshot | null>(null);
  const olderLast = useRef<QueryDocumentSnapshot | null>(null);

  // First page: live.
  useEffect(() => {
    setById(new Map());
    liveLast.current = null;
    olderLast.current = null;
    setHasMore(true);

    if (!workspaceId) {
      setLoading(false);
      return;
    }
    setLoading(true);

    const q = query(
      collection(db, "revisions"),
      where("workspaceId", "==", workspaceId),
      orderBy("at", "desc"),
      limit(ACTIVITY_PAGE_SIZE),
    );
    const unsub = onSnapshot(
      q,
      (snap) => {
        liveLast.current = snap.docs[snap.docs.length - 1] ?? null;
        setById((prev) => {
          const next = new Map(prev);
          for (const d of snap.docs) next.set(d.id, d.data() as Revision);
          return next;
        });
        // If the first live page isn't full and we've not paged yet, there's
        // nothing older to fetch.
        if (olderLast.current === null && snap.size < ACTIVITY_PAGE_SIZE) {
          setHasMore(false);
        }
        setError(null);
        setLoading(false);
      },
      (e) => {
        setError(e.message);
        setLoading(false);
      },
    );
    return unsub;
  }, [workspaceId]);

  const loadMore = useCallback(() => {
    if (!workspaceId || loadingMore || !hasMore) return;
    const cursor = olderLast.current ?? liveLast.current;
    if (!cursor) return;

    setLoadingMore(true);
    const q = query(
      collection(db, "revisions"),
      where("workspaceId", "==", workspaceId),
      orderBy("at", "desc"),
      startAfter(cursor),
      limit(ACTIVITY_PAGE_SIZE),
    );
    getDocs(q)
      .then((snap) => {
        if (snap.docs.length > 0) {
          olderLast.current = snap.docs[snap.docs.length - 1];
          setById((prev) => {
            const next = new Map(prev);
            for (const d of snap.docs) next.set(d.id, d.data() as Revision);
            return next;
          });
        }
        if (snap.size < ACTIVITY_PAGE_SIZE) setHasMore(false);
      })
      .catch((e) => setError(e instanceof Error ? e.message : "Failed to load older activity"))
      .finally(() => setLoadingMore(false));
  }, [workspaceId, loadingMore, hasMore]);

  const activity = useMemo(
    () =>
      [...byId.values()].sort((a, b) => {
        const ta = a.at ? toDate(a.at).getTime() : 0;
        const tb = b.at ? toDate(b.at).getTime() : 0;
        return tb - ta;
      }),
    [byId],
  );

  return { activity, loading, loadingMore, hasMore, loadMore, error };
}
