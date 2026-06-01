// Workspace + permission context (§6 "Global"). For the signed-in user this:
//   - loads all memberships (live),
//   - resolves the active workspace, PER TAB (sessionStorage) so multiple tabs
//     can work on different workspaces simultaneously,
//   - loads the active workspace doc + the user's role for it (live),
//   - exposes `can(perm)` used to gate every nav item, route and action.

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import {
  collection,
  doc,
  getDoc,
  onSnapshot,
  query,
  setDoc,
  where,
} from "firebase/firestore";
import { db } from "@/firebase/config";
import { subscribeWithRetry } from "@/lib/firestoreRetry";
import { setCurrentWorkspaceId } from "@/data/actor";
import { useAuth } from "@/auth/AuthProvider";
import type { Membership, Role, Workspace } from "@/types/models";
import type { Permission } from "@/types/permissions";

interface WorkspaceState {
  loading: boolean;
  error: string | null;
  memberships: Membership[];
  workspaces: Workspace[];
  activeWorkspaceId: string | null;
  activeWorkspace: Workspace | null;
  role: Role | null;
  can: (perm: Permission) => boolean;
  switchWorkspace: (workspaceId: string) => void;
}

const WorkspaceContext = createContext<WorkspaceState | undefined>(undefined);

// Per-tab active workspace. sessionStorage is scoped to a single tab, so two
// tabs can hold different active workspaces at once (req: multi-tab).
const tabKey = (uid: string) => `active-workspace:${uid}`;
function readTabWorkspace(uid: string): string | null {
  try {
    return sessionStorage.getItem(tabKey(uid));
  } catch {
    return null;
  }
}
function writeTabWorkspace(uid: string, workspaceId: string) {
  try {
    sessionStorage.setItem(tabKey(uid), workspaceId);
  } catch {
    /* storage unavailable — fall back to in-memory state only */
  }
}

export function WorkspaceProvider({ children }: { children: ReactNode }) {
  const { firebaseUser } = useAuth();
  const uid = firebaseUser?.uid ?? null;

  const [memberships, setMemberships] = useState<Membership[]>([]);
  const [workspaces, setWorkspaces] = useState<Workspace[]>([]);
  const [activeWorkspaceId, setActiveWorkspaceId] = useState<string | null>(null);
  const [role, setRole] = useState<Role | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // The preferred workspace to open on load: this tab's last choice
  // (sessionStorage), else the user's cross-session lastWorkspaceId. Resolved
  // once per uid. We hold it in a ref + a "ready" flag so the memberships
  // listener doesn't prematurely fall back to the first membership before the
  // preference is known (that race opened the wrong workspace on every load).
  const preferredId = useRef<string | null>(null);
  const [prefReady, setPrefReady] = useState(false);

  useEffect(() => {
    if (!uid) return;
    let cancelled = false;
    preferredId.current = null;
    setPrefReady(false);

    const fromTab = readTabWorkspace(uid);
    if (fromTab) {
      preferredId.current = fromTab;
      setPrefReady(true);
      return;
    }
    void getDoc(doc(db, "users", uid))
      .then((snap) => {
        if (cancelled) return;
        const last = (snap.data() as { lastWorkspaceId?: string } | undefined)?.lastWorkspaceId;
        preferredId.current = last ?? null;
      })
      .finally(() => {
        if (!cancelled) setPrefReady(true);
      });
    return () => {
      cancelled = true;
    };
  }, [uid]);

  // memberships of the current user
  useEffect(() => {
    if (!uid) {
      setMemberships([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    const q = query(collection(db, "memberships"), where("uid", "==", uid));
    const unsub = onSnapshot(
      q,
      (snap) => {
        const list = snap.docs.map((d) => d.data() as Membership);
        setMemberships(list);
        setLoading(false);
      },
      (e) => {
        setError(e.message);
        setLoading(false);
      },
    );
    return unsub;
  }, [uid]);

  // Resolve the active workspace once BOTH the preference and the memberships
  // are available — preferring the saved choice, then the first membership.
  // Also self-heals if the current selection is removed (e.g. workspace
  // deleted or membership revoked).
  useEffect(() => {
    if (!prefReady) return;
    setActiveWorkspaceId((current) => {
      if (current && memberships.some((m) => m.workspaceId === current)) return current;
      const pref = preferredId.current;
      if (pref && memberships.some((m) => m.workspaceId === pref)) return pref;
      return memberships[0]?.workspaceId ?? null;
    });
  }, [prefReady, memberships]);

  // workspace docs for all memberships
  useEffect(() => {
    if (memberships.length === 0) {
      setWorkspaces([]);
      return;
    }
    const ids = memberships.map((m) => m.workspaceId);
    // Firestore `in` supports up to 30 ids; fine for typical membership counts.
    const q = query(collection(db, "workspaces"), where("__name__", "in", ids));
    // Retry on transient permission-denied: when a new workspace+membership
    // batch is created, listeners re-fire optimistically before the server
    // commits, briefly failing the rules check.
    const unsub = subscribeWithRetry(
      q,
      (snap) => {
        setWorkspaces(snap.docs.map((d) => d.data() as Workspace));
        setError(null);
      },
      (e) => setError(e.message),
    );
    return unsub;
  }, [memberships]);

  // persist this tab's active workspace whenever it changes + expose it to the
  // mutation layer (for audit/revision stamping)
  useEffect(() => {
    setCurrentWorkspaceId(activeWorkspaceId);
    if (uid && activeWorkspaceId) writeTabWorkspace(uid, activeWorkspaceId);
  }, [uid, activeWorkspaceId]);

  // role for the active workspace
  useEffect(() => {
    if (!activeWorkspaceId) {
      setRole(null);
      return;
    }
    const membership = memberships.find((m) => m.workspaceId === activeWorkspaceId);
    if (!membership) {
      setRole(null);
      return;
    }
    const unsub = subscribeWithRetry(
      doc(db, "roles", membership.roleId),
      (snap) => {
        setRole(snap.exists() ? (snap.data() as Role) : null);
        setError(null);
      },
      (e) => setError(e.message),
    );
    return unsub;
  }, [activeWorkspaceId, memberships]);

  const activeWorkspace =
    workspaces.find((w) => w.id === activeWorkspaceId) ?? null;

  const value = useMemo<WorkspaceState>(() => {
    // The workspace owner implicitly holds every permission — mirroring the
    // owner-bypass in the Security Rules. This also means owners are never
    // locked out of a newly added permission (e.g. `shared.*`) by a role doc
    // that was seeded before that permission existed.
    const isOwner = !!uid && activeWorkspace?.ownerId === uid;
    const can = (perm: Permission) => isOwner || role?.permissions?.[perm] === true;
    const switchWorkspace = (workspaceId: string) => {
      setActiveWorkspaceId(workspaceId);
      if (uid) {
        writeTabWorkspace(uid, workspaceId); // this tab
        // also update the cross-session default for fresh logins / new tabs
        void setDoc(
          doc(db, "users", uid),
          { lastWorkspaceId: workspaceId },
          { merge: true },
        );
      }
    };
    return {
      loading,
      error,
      memberships,
      workspaces,
      activeWorkspaceId,
      activeWorkspace,
      role,
      can,
      switchWorkspace,
    };
  }, [
    loading,
    error,
    memberships,
    workspaces,
    activeWorkspaceId,
    activeWorkspace,
    role,
    uid,
  ]);

  return (
    <WorkspaceContext.Provider value={value}>
      {children}
    </WorkspaceContext.Provider>
  );
}

export function useWorkspace(): WorkspaceState {
  const ctx = useContext(WorkspaceContext);
  if (!ctx) throw new Error("useWorkspace must be used within <WorkspaceProvider>");
  return ctx;
}

/** Convenience hook: permission check for the active workspace. */
export function useCan(): (perm: Permission) => boolean {
  return useWorkspace().can;
}
