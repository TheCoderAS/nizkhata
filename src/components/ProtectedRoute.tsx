// Route guards. Auth gate (must be signed in) and permission gate (must hold a
// permission in the active workspace). Rules are the real enforcement; this is
// UX only (§6 "Hide, don't disable").

import type { ReactNode } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { FullScreenLoader, LoadingState, NoPermissionState } from "./states";
import type { Permission } from "@/types/permissions";

export function RequireAuth({ children }: { children: ReactNode }) {
  const { firebaseUser, loading } = useAuth();
  const location = useLocation();
  if (loading) return <FullScreenLoader label="Signing in…" />;
  if (!firebaseUser)
    return <Navigate to="/login" replace state={{ from: location }} />;
  return <>{children}</>;
}

export function RequirePermission({
  perm,
  children,
}: {
  perm: Permission;
  children: ReactNode;
}) {
  const { loading, can } = useWorkspace();
  if (loading) return <LoadingState />;
  if (!can(perm)) return <NoPermissionState perm={perm} />;
  return <>{children}</>;
}
