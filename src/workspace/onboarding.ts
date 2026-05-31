// Onboarding / invite logic (§5).
//
// On first (and every) login:
//   1. upsert users/{uid}
//   2. claim any pending invites for this email -> create membership, mark
//      invite accepted (deterministic invite ids; see rules FIX 1)
//   3. if the user ends up with no memberships, auto-create a personal
//      workspace: workspace doc (committed first, so the owner bypass in rules
//      resolves), then seed 4 system roles + owner membership + default
//      categories in a batch.
//   4. set lastWorkspaceId.

import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  where,
  writeBatch,
  type Firestore,
} from "firebase/firestore";
import type { User as FirebaseUser } from "firebase/auth";
import { db } from "@/firebase/config";
import { DEFAULT_CATEGORIES, systemRoleSpecs } from "./seed";

function inviteId(workspaceId: string, email: string): string {
  return `${workspaceId}_${email.toLowerCase()}`;
}

/** Run an optional onboarding step without letting its failure abort sign-in. */
async function bestEffort(label: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
  } catch (e) {
    console.warn(`[onboarding] optional step "${label}" failed (continuing):`, e);
  }
}

/** Upsert the user profile doc. */
async function upsertUser(fdb: Firestore, user: FirebaseUser): Promise<void> {
  const ref = doc(fdb, "users", user.uid);
  const snap = await getDoc(ref);
  const email = (user.email ?? "").toLowerCase();
  if (!snap.exists()) {
    await setDoc(ref, {
      uid: user.uid,
      email,
      displayName: user.displayName ?? null,
      photoURL: user.photoURL ?? null,
      createdAt: serverTimestamp(),
      lastWorkspaceId: null,
    });
  } else {
    // keep email/displayName/photo fresh, leave lastWorkspaceId alone
    await setDoc(
      ref,
      {
        email,
        displayName: user.displayName ?? null,
        photoURL: user.photoURL ?? null,
      },
      { merge: true },
    );
  }
}

/** Claim all pending invites for this email. Returns claimed workspaceIds. */
async function claimInvites(
  fdb: Firestore,
  user: FirebaseUser,
): Promise<string[]> {
  const email = (user.email ?? "").toLowerCase();
  if (!email) return [];

  const q = query(
    collection(fdb, "invites"),
    where("email", "==", email),
    where("status", "==", "pending"),
  );
  const snap = await getDocs(q);
  const claimed: string[] = [];

  for (const inviteSnap of snap.docs) {
    const invite = inviteSnap.data() as {
      workspaceId: string;
      roleId: string;
      expiresAt?: { toMillis(): number };
    };
    // skip expired invites
    if (invite.expiresAt && invite.expiresAt.toMillis() < Date.now()) continue;

    const membershipId = `${invite.workspaceId}_${user.uid}`;
    const batch = writeBatch(fdb);
    batch.set(doc(fdb, "memberships", membershipId), {
      id: membershipId,
      workspaceId: invite.workspaceId,
      uid: user.uid,
      roleId: invite.roleId,
      status: "active",
      joinedAt: serverTimestamp(),
      email: (user.email ?? "").toLowerCase(),
      displayName: user.displayName ?? null,
    });
    batch.set(
      doc(fdb, "invites", inviteSnap.id),
      { status: "accepted" },
      { merge: true },
    );
    await batch.commit();
    claimed.push(invite.workspaceId);
  }
  return claimed;
}

/**
 * Claim pending cross-user share invites addressed to this user's email:
 * establish the `sharedConnection` and mark each invite accepted. Establishes
 * NO workspace access — share partners only ever appear in the Shared section.
 */
async function claimShareInvites(fdb: Firestore, user: FirebaseUser): Promise<void> {
  const email = (user.email ?? "").toLowerCase();
  if (!email) return;

  const q = query(
    collection(fdb, "shareInvites"),
    where("toEmail", "==", email),
    where("status", "==", "pending"),
  );
  const snap = await getDocs(q);

  for (const inviteSnap of snap.docs) {
    const invite = inviteSnap.data() as {
      fromUid: string;
      fromName: string;
      fromEmail: string;
      expiresAt?: { toMillis(): number };
    };
    if (invite.expiresAt && invite.expiresAt.toMillis() < Date.now()) continue;

    const connId = [invite.fromUid, user.uid].sort().join("_");
    const meName =
      user.displayName?.trim() || email || `${user.uid.slice(0, 8)}…`;
    const batch = writeBatch(fdb);
    batch.set(doc(fdb, "sharedConnections", connId), {
      id: connId,
      uids: [invite.fromUid, user.uid].sort(),
      names: { [invite.fromUid]: invite.fromName, [user.uid]: meName },
      emails: { [invite.fromUid]: invite.fromEmail, [user.uid]: email },
      status: "active",
      createdAt: serverTimestamp(),
    });
    batch.set(doc(fdb, "shareInvites", inviteSnap.id), { status: "accepted" }, { merge: true });
    await batch.commit();
  }
}

/**
 * Keep the seeded system roles in step with the current permission catalog.
 * As new permissions are added (e.g. `shared.*`), existing workspaces' system
 * roles would otherwise be missing them and silently lock owners/editors out of
 * new sections. For every workspace this user OWNS (owner holds `roles.manage`
 * + the rules owner-bypass), re-apply the template permissions to any system
 * role whose stored map differs. Idempotent and cheap (writes only on drift).
 */
async function syncSystemRoles(fdb: Firestore, user: FirebaseUser): Promise<void> {
  const ownedQ = query(collection(fdb, "workspaces"), where("ownerId", "==", user.uid));
  const owned = await getDocs(ownedQ);
  if (owned.empty) return;

  const templateByName = Object.fromEntries(
    systemRoleSpecs().map((s) => [s.name, s.permissions]),
  );

  for (const wsSnap of owned.docs) {
    const workspaceId = wsSnap.id;
    const rolesSnap = await getDocs(
      query(
        collection(fdb, "roles"),
        where("workspaceId", "==", workspaceId),
        where("isSystem", "==", true),
      ),
    );
    const batch = writeBatch(fdb);
    let dirty = false;
    for (const roleSnap of rolesSnap.docs) {
      const role = roleSnap.data() as { name: string; permissions: Record<string, boolean> };
      const template = templateByName[role.name];
      if (!template) continue;
      if (JSON.stringify(role.permissions) !== JSON.stringify(template)) {
        batch.set(doc(fdb, "roles", roleSnap.id), { permissions: template }, { merge: true });
        dirty = true;
      }
    }
    if (dirty) await batch.commit();
  }
}

/** List workspaceIds the user is a member of. */
async function listMembershipWorkspaceIds(
  fdb: Firestore,
  uid: string,
): Promise<string[]> {
  const q = query(collection(fdb, "memberships"), where("uid", "==", uid));
  const snap = await getDocs(q);
  return snap.docs.map((d) => (d.data() as { workspaceId: string }).workspaceId);
}

/**
 * Create a workspace and seed roles + owner membership + categories. Returns the
 * new workspaceId. If `name` is omitted, a personal-workspace name is derived
 * from the user's display name. Reused by first-login onboarding and the
 * "add workspace" flow.
 */
async function createPersonalWorkspace(
  fdb: Firestore,
  user: FirebaseUser,
  name?: string,
): Promise<string> {
  // 1) workspace doc committed FIRST so the owner-bypass in rules resolves
  //    for the subsequent role/membership/category seed writes.
  const wsRef = doc(collection(fdb, "workspaces"));
  const workspaceId = wsRef.id;
  const workspaceName =
    name?.trim() ||
    (user.displayName
      ? `${user.displayName.split(" ")[0]}'s Workspace`
      : "My Workspace");
  await setDoc(wsRef, {
    id: workspaceId,
    name: workspaceName,
    ownerId: user.uid,
    baseCurrency: "INR",
    fyStartMonth: 4, // April (India)
    createdAt: serverTimestamp(),
  });

  // 2) seed roles, owner membership, categories in one batch
  const batch = writeBatch(fdb);

  let ownerRoleId = "";
  for (const spec of systemRoleSpecs()) {
    const roleRef = doc(collection(fdb, "roles"));
    if (spec.name === "Owner") ownerRoleId = roleRef.id;
    batch.set(roleRef, {
      id: roleRef.id,
      workspaceId,
      name: spec.name,
      isSystem: true,
      permissions: spec.permissions,
      createdAt: serverTimestamp(),
    });
  }

  const membershipId = `${workspaceId}_${user.uid}`;
  batch.set(doc(fdb, "memberships", membershipId), {
    id: membershipId,
    workspaceId,
    uid: user.uid,
    roleId: ownerRoleId,
    status: "active",
    joinedAt: serverTimestamp(),
    email: (user.email ?? "").toLowerCase(),
    displayName: user.displayName ?? null,
  });

  for (const cat of DEFAULT_CATEGORIES) {
    const catRef = doc(collection(fdb, "categories"));
    batch.set(catRef, {
      id: catRef.id,
      workspaceId,
      name: cat.name,
      kind: cat.kind,
      isSystem: true,
      createdAt: serverTimestamp(),
    });
  }

  await batch.commit();
  return workspaceId;
}

/**
 * Idempotent first-login flow. Safe to call on every auth state change.
 */
export async function ensureUserAndOnboarding(
  user: FirebaseUser,
  fdb: Firestore = db,
): Promise<void> {
  await upsertUser(fdb, user);
  await claimInvites(fdb, user);
  // Enhancement steps — best-effort. A failure here (e.g. the shared-ledger
  // rules not yet deployed) must NOT block sign-in, so swallow + log rather
  // than reject the whole onboarding.
  await bestEffort("claimShareInvites", () => claimShareInvites(fdb, user));
  await bestEffort("syncSystemRoles", () => syncSystemRoles(fdb, user));

  let workspaceIds = await listMembershipWorkspaceIds(fdb, user.uid);
  if (workspaceIds.length === 0) {
    const wsId = await createPersonalWorkspace(fdb, user);
    workspaceIds = [wsId];
  }

  // set lastWorkspaceId if unset
  const userRef = doc(fdb, "users", user.uid);
  const snap = await getDoc(userRef);
  const data = snap.data() as { lastWorkspaceId?: string | null } | undefined;
  if (!data?.lastWorkspaceId && workspaceIds.length > 0) {
    await setDoc(userRef, { lastWorkspaceId: workspaceIds[0] }, { merge: true });
  }
}

export { inviteId };

/**
 * Public helper: create an additional workspace owned by the current user
 * (seeded with system roles, owner membership and default categories).
 * Returns the new workspaceId.
 */
export async function createWorkspace(
  user: FirebaseUser,
  name: string,
  fdb: Firestore = db,
): Promise<string> {
  return createPersonalWorkspace(fdb, user, name);
}
