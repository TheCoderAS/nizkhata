// Workspace + permission context (§6 "Global"). For the signed-in user this:
//   - loads all memberships (live),
//   - resolves the active workspace (lastWorkspaceId, switchable),
//   - loads the active workspace doc + the user's role for it (live),
//   - exposes `can(perm)` used to gate every nav item, route and action.

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  collection,
  doc,
  onSnapshot,
  query,
  setDoc,
  where,
} from "firebase/firestore";
import { db } from "@/firebase/config";
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

export function WorkspaceProvider({ children }: { children: ReactNode }) {
  const { firebaseUser } = useAuth();
  const uid = firebaseUser?.uid ?? null;

  const [memberships, setMemberships] = useState<Membership[]>([]);
  const [workspaces, setWorkspaces] = useState<Workspace[]>([]);
  const [activeWorkspaceId, setActiveWorkspaceId] = useState<string | null>(null);
  const [role, setRole] = useState<Role | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

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
        setActiveWorkspaceId((current) => {
          if (current && list.some((m) => m.workspaceId === current)) return current;
          return list[0]?.workspaceId ?? null;
        });
        setLoading(false);
      },
      (e) => {
        setError(e.message);
        setLoading(false);
      },
    );
    return unsub;
  }, [uid]);

  // workspace docs for all memberships
  useEffect(() => {
    if (memberships.length === 0) {
      setWorkspaces([]);
      return;
    }
    const ids = memberships.map((m) => m.workspaceId);
    // Firestore `in` supports up to 30 ids; fine for typical membership counts.
    const q = query(collection(db, "workspaces"), where("__name__", "in", ids));
    const unsub = onSnapshot(
      q,
      (snap) => setWorkspaces(snap.docs.map((d) => d.data() as Workspace)),
      (e) => setError(e.message),
    );
    return unsub;
  }, [memberships]);

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
    const unsub = onSnapshot(
      doc(db, "roles", membership.roleId),
      (snap) => setRole(snap.exists() ? (snap.data() as Role) : null),
      (e) => setError(e.message),
    );
    return unsub;
  }, [activeWorkspaceId, memberships]);

  const activeWorkspace =
    workspaces.find((w) => w.id === activeWorkspaceId) ?? null;

  const value = useMemo<WorkspaceState>(() => {
    const can = (perm: Permission) => role?.permissions?.[perm] === true;
    const switchWorkspace = (workspaceId: string) => {
      setActiveWorkspaceId(workspaceId);
      if (uid) {
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
