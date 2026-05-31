// Live subscriptions for the cross-user shared ledger. Unlike
// WorkspaceDataProvider, these are scoped by the signed-in user's uid (and
// email), NOT by workspace — the same partners/entries are visible no matter
// which workspace is active. Powers the Shared section and its inbox badge.

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { collection, orderBy, query, where } from "firebase/firestore";
import { db } from "@/firebase/config";
import { subscribeWithRetry } from "@/lib/firestoreRetry";
import { useAuth } from "@/auth/AuthProvider";
import type { SharedConnection, SharedEntry, ShareInvite } from "@/types/models";

interface SharedData {
  loading: boolean;
  error: string | null;
  connections: SharedConnection[];
  entries: SharedEntry[];
  // share invites I sent (pending/accepted) and those addressed to me
  sentInvites: ShareInvite[];
  // entries awaiting MY response (the inbox)
  inboxCount: number;
}

const SharedContext = createContext<SharedData | undefined>(undefined);

export function SharedDataProvider({ children }: { children: ReactNode }) {
  const { firebaseUser } = useAuth();
  const uid = firebaseUser?.uid ?? null;

  const [connections, setConnections] = useState<SharedConnection[]>([]);
  const [entries, setEntries] = useState<SharedEntry[]>([]);
  const [sentInvites, setSentInvites] = useState<ShareInvite[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!uid) {
      setConnections([]);
      setEntries([]);
      setSentInvites([]);
      setLoading(false);
      return;
    }
    setLoading(true);

    const unsubConn = subscribeWithRetry(
      query(collection(db, "sharedConnections"), where("uids", "array-contains", uid)),
      (snap) => {
        setConnections(snap.docs.map((d) => d.data() as SharedConnection));
        setError(null);
      },
      (e) => setError(e.message),
    );

    const unsubEntries = subscribeWithRetry(
      query(
        collection(db, "sharedEntries"),
        where("uids", "array-contains", uid),
        orderBy("date", "desc"),
      ),
      (snap) => {
        setEntries(snap.docs.map((d) => d.data() as SharedEntry));
        setError(null);
        setLoading(false);
      },
      (e) => {
        setError(e.message);
        setLoading(false);
      },
    );

    const unsubInvites = subscribeWithRetry(
      query(collection(db, "shareInvites"), where("fromUid", "==", uid)),
      (snap) => setSentInvites(snap.docs.map((d) => d.data() as ShareInvite)),
      (e) => setError(e.message),
    );

    return () => {
      unsubConn();
      unsubEntries();
      unsubInvites();
    };
  }, [uid]);

  const value = useMemo<SharedData>(() => {
    const inboxCount = uid
      ? entries.filter((e) => (e.pendingForUids ?? []).includes(uid)).length
      : 0;
    return { loading, error, connections, entries, sentInvites, inboxCount };
  }, [loading, error, connections, entries, sentInvites, uid]);

  return <SharedContext.Provider value={value}>{children}</SharedContext.Provider>;
}

export function useSharedData(): SharedData {
  const ctx = useContext(SharedContext);
  if (!ctx) throw new Error("useSharedData must be used within <SharedDataProvider>");
  return ctx;
}
