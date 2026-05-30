// Members / roles / invites mutations (§3 guardrails, §5 invites). Permission is
// independently enforced by Security Rules; some guardrails (last-holder, role
// in-use) can only live in app logic and are checked here before writing.

import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";
import { db } from "@/firebase/config";
import type { Membership, Role } from "@/types/models";
import type { PermissionMap, Permission } from "@/types/permissions";

function newId(name: string): string {
  return doc(collection(db, name)).id;
}

export function inviteId(workspaceId: string, email: string): string {
  return `${workspaceId}_${email.toLowerCase()}`;
}

// ---- roles -----------------------------------------------------------------

export async function createRole(
  workspaceId: string,
  name: string,
  permissions: PermissionMap,
): Promise<string> {
  const id = newId("roles");
  await setDoc(doc(db, "roles", id), {
    id,
    workspaceId,
    name,
    isSystem: false,
    permissions,
    createdAt: serverTimestamp(),
  });
  return id;
}

export async function updateRole(
  id: string,
  data: Partial<Pick<Role, "name" | "permissions">>,
) {
  await updateDoc(doc(db, "roles", id), data);
}

export async function duplicateRole(
  workspaceId: string,
  source: Role,
): Promise<string> {
  return createRole(workspaceId, `${source.name} (copy)`, { ...source.permissions });
}

export class GuardrailError extends Error {}

export async function deleteRole(
  role: Role,
  allMemberships: Membership[],
): Promise<void> {
  if (role.isSystem)
    throw new GuardrailError("System roles can't be deleted — duplicate to customize.");
  if (allMemberships.some((m) => m.roleId === role.id))
    throw new GuardrailError("This role is assigned to a member; reassign them first.");
  await deleteDoc(doc(db, "roles", role.id));
}

/** Count how many active members effectively hold a permission. */
function holdersOf(
  perm: Permission,
  memberships: Membership[],
  rolesById: Record<string, Role>,
): number {
  return memberships.filter((m) => rolesById[m.roleId]?.permissions?.[perm] === true).length;
}

/**
 * Guard before changing a role/permission set or a member's role: don't strip
 * the last holder of roles.manage or members.remove.
 */
export function assertNotLastHolder(
  perm: Permission,
  memberships: Membership[],
  rolesById: Record<string, Role>,
): void {
  if (holdersOf(perm, memberships, rolesById) <= 1)
    throw new GuardrailError(
      `Can't remove the last member who can "${perm}".`,
    );
}

// ---- memberships -----------------------------------------------------------

export async function changeMemberRole(
  membership: Membership,
  newRoleId: string,
  ownerId: string,
): Promise<void> {
  if (membership.uid === ownerId)
    throw new GuardrailError("The workspace owner's role can't be changed.");
  await updateDoc(doc(db, "memberships", membership.id), { roleId: newRoleId });
}

export async function removeMember(
  membership: Membership,
  ownerId: string,
): Promise<void> {
  if (membership.uid === ownerId)
    throw new GuardrailError("The workspace owner can't be removed.");
  await deleteDoc(doc(db, "memberships", membership.id));
}

// ---- invites ---------------------------------------------------------------

export async function createInvite(
  workspaceId: string,
  email: string,
  roleId: string,
  invitedBy: string,
): Promise<string> {
  const id = inviteId(workspaceId, email);
  const expiresAt = Timestamp.fromDate(new Date(Date.now() + 14 * 24 * 60 * 60 * 1000));
  await setDoc(doc(db, "invites", id), {
    id,
    workspaceId,
    email: email.toLowerCase(),
    roleId,
    status: "pending",
    invitedBy,
    createdAt: serverTimestamp(),
    expiresAt,
  });
  return id;
}

export async function revokeInvite(id: string): Promise<void> {
  await updateDoc(doc(db, "invites", id), { status: "revoked" });
}
