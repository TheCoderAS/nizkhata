// Resolve the current user's denormalized Actor (uid + best display name) for
// audit fields and revisions. Name preference: Firebase displayName -> email ->
// short uid. Stored on each write so history reads don't need other users'
// profiles (which Security Rules forbid).

import type { User as FirebaseUser } from "firebase/auth";
import type { Actor } from "@/types/models";

export function actorFromUser(user: FirebaseUser | null): Actor {
  if (!user) return { uid: "", name: "Unknown" };
  const name =
    user.displayName?.trim() ||
    (user.email ? user.email.toLowerCase() : "") ||
    `${user.uid.slice(0, 8)}…`;
  return { uid: user.uid, name };
}

// Module-level holders so plain mutation functions can stamp audit fields +
// revisions without every caller threading actor/workspace through.
//   - actor: set by AuthProvider on auth change
//   - workspace: set by WorkspaceProvider when the active workspace changes
let _current: Actor = { uid: "", name: "Unknown" };
let _workspaceId = "";

export function setCurrentActor(actor: Actor): void {
  _current = actor;
}

export function getCurrentActor(): Actor {
  return _current;
}

export function setCurrentWorkspaceId(id: string | null): void {
  _workspaceId = id ?? "";
}

export function getCurrentWorkspaceId(): string {
  return _workspaceId;
}
