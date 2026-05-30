// Live admin data for the Settings screens: all memberships, roles and invites
// for the active workspace. Kept separate from WorkspaceDataProvider because most
// screens don't need it.

import { useEffect, useState } from "react";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { db } from "@/firebase/config";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import type { Invite, Membership, Role } from "@/types/models";

export function useAdminData() {
  const { activeWorkspaceId } = useWorkspace();
  const [memberships, setMemberships] = useState<Membership[]>([]);
  const [roles, setRoles] = useState<Role[]>([]);
  const [invites, setInvites] = useState<Invite[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!activeWorkspaceId) return;
    setLoading(true);
    const subs = [
      onSnapshot(
        query(collection(db, "memberships"), where("workspaceId", "==", activeWorkspaceId)),
        (s) => {
          setMemberships(s.docs.map((d) => d.data() as Membership));
          setLoading(false);
        },
        (e) => setError(e.message),
      ),
      onSnapshot(
        query(collection(db, "roles"), where("workspaceId", "==", activeWorkspaceId)),
        (s) => setRoles(s.docs.map((d) => d.data() as Role)),
        (e) => setError(e.message),
      ),
      onSnapshot(
        query(collection(db, "invites"), where("workspaceId", "==", activeWorkspaceId)),
        (s) => setInvites(s.docs.map((d) => d.data() as Invite)),
        (e) => setError(e.message),
      ),
    ];
    return () => subs.forEach((u) => u());
  }, [activeWorkspaceId]);

  const rolesById = Object.fromEntries(roles.map((r) => [r.id, r]));

  return { memberships, roles, rolesById, invites, loading, error };
}
