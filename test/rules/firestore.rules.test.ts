// Security Rules matrix (§4, §8 "Definition of done").
//
// Requires the Firestore emulator + Java. Run with:
//   firebase emulators:exec --only firestore "npm run test:rules"
//
// Covers: membership-gated reads, permission-gated CRUD per collection,
// cross-workspace denial, the bootstrap owner-bypass, and the tightened
// membership self-join (rules FIX 1).

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "node:fs";
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

const PROJECT_ID = "rules-test";
const WS = "ws1";
const OTHER_WS = "ws2";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync("firestore.rules", "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterAll(async () => env?.cleanup());

// Seed a workspace with an Owner role + a Viewer role, and one owner membership.
async function seedWorkspace(workspaceId: string, ownerUid: string) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "workspaces", workspaceId), {
      id: workspaceId,
      name: "Book",
      ownerId: ownerUid,
      baseCurrency: "INR",
      fyStartMonth: 4,
    });
    await setDoc(doc(db, "roles", `${workspaceId}_owner`), {
      id: `${workspaceId}_owner`,
      workspaceId,
      name: "Owner",
      isSystem: true,
      permissions: allPerms(true),
    });
    await setDoc(doc(db, "roles", `${workspaceId}_viewer`), {
      id: `${workspaceId}_viewer`,
      workspaceId,
      name: "Viewer",
      isSystem: true,
      permissions: { ...allPerms(false), "transactions.view": true, "accounts.view": true },
    });
    await setDoc(doc(db, "memberships", `${workspaceId}_${ownerUid}`), {
      id: `${workspaceId}_${ownerUid}`,
      workspaceId,
      uid: ownerUid,
      roleId: `${workspaceId}_owner`,
      status: "active",
    });
  });
}

function allPerms(value: boolean) {
  const keys = [
    "transactions.view","transactions.create","transactions.edit","transactions.delete",
    "accounts.view","accounts.manage","categories.view","categories.manage",
    "contacts.view","contacts.manage","debts.view","debts.manage",
    "dues.view","dues.manage","shared.view","shared.manage",
    "reports.view","reports.export",
    "members.view","members.invite","members.remove","roles.view","roles.manage",
    "workspace.edit","workspace.delete",
  ];
  return Object.fromEntries(keys.map((k) => [k, value]));
}

beforeEach(async () => {
  await env.clearFirestore();
  await seedWorkspace(WS, "owner");
  await seedWorkspace(OTHER_WS, "stranger");
});

describe("membership-gated reads", () => {
  it("a member can read their workspace", async () => {
    const db = env.authenticatedContext("owner").firestore();
    await assertSucceeds(getDoc(doc(db, "workspaces", WS)));
  });
  it("a non-member cannot read a workspace", async () => {
    const db = env.authenticatedContext("nobody").firestore();
    await assertFails(getDoc(doc(db, "workspaces", WS)));
  });
});

describe("cross-workspace denial", () => {
  it("owner of ws1 cannot read ws2 accounts", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "accounts", "a2"), {
        id: "a2", workspaceId: OTHER_WS, name: "Other", type: "cash", openingBalance: 0,
      });
    });
    const db = env.authenticatedContext("owner").firestore();
    await assertFails(getDoc(doc(db, "accounts", "a2")));
  });
});

describe("permission-gated writes", () => {
  it("owner (accounts.manage) can create an account", async () => {
    const db = env.authenticatedContext("owner").firestore();
    await assertSucceeds(
      setDoc(doc(db, "accounts", "a1"), {
        id: "a1", workspaceId: WS, name: "Cash", type: "cash", openingBalance: 0,
      }),
    );
  });
  it("viewer (no accounts.manage) cannot create an account", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "memberships", `${WS}_viewer`), {
        id: `${WS}_viewer`, workspaceId: WS, uid: "viewer",
        roleId: `${WS}_viewer`, status: "active",
      });
    });
    const db = env.authenticatedContext("viewer").firestore();
    await assertFails(
      setDoc(doc(db, "accounts", "a9"), {
        id: "a9", workspaceId: WS, name: "X", type: "cash", openingBalance: 0,
      }),
    );
  });
  it("a transaction must set createdBy to the caller", async () => {
    const db = env.authenticatedContext("owner").firestore();
    await assertFails(
      setDoc(doc(db, "transactions", "t1"), {
        id: "t1", workspaceId: WS, accountId: "a1", totalAmount: 0,
        hasSplit: false, financialYear: "2025-26", createdBy: "someone-else", lines: [],
      }),
    );
    await assertSucceeds(
      setDoc(doc(db, "transactions", "t2"), {
        id: "t2", workspaceId: WS, accountId: "a1", totalAmount: 0,
        hasSplit: false, financialYear: "2025-26", createdBy: "owner", lines: [],
      }),
    );
  });
});

describe("FIX 1 — no open membership self-join", () => {
  it("a stranger cannot mint themselves a membership without an invite", async () => {
    const db = env.authenticatedContext("intruder").firestore();
    await assertFails(
      setDoc(doc(db, "memberships", `${WS}_intruder`), {
        id: `${WS}_intruder`, workspaceId: WS, uid: "intruder",
        roleId: `${WS}_owner`, status: "active",
      }),
    );
  });

  it("an invited user CAN claim a matching pending invite", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "invites", `${WS}_guest@x.com`), {
        id: `${WS}_guest@x.com`, workspaceId: WS, email: "guest@x.com",
        roleId: `${WS}_viewer`, status: "pending", invitedBy: "owner",
      });
    });
    const db = env
      .authenticatedContext("guest", { email: "guest@x.com" })
      .firestore();
    await assertSucceeds(
      setDoc(doc(db, "memberships", `${WS}_guest`), {
        id: `${WS}_guest`, workspaceId: WS, uid: "guest",
        roleId: `${WS}_viewer`, status: "active",
      }),
    );
  });

  it("an invited user cannot escalate to a role other than the invite's", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "invites", `${WS}_guest@x.com`), {
        id: `${WS}_guest@x.com`, workspaceId: WS, email: "guest@x.com",
        roleId: `${WS}_viewer`, status: "pending", invitedBy: "owner",
      });
    });
    const db = env
      .authenticatedContext("guest", { email: "guest@x.com" })
      .firestore();
    await assertFails(
      setDoc(doc(db, "memberships", `${WS}_guest`), {
        id: `${WS}_guest`, workspaceId: WS, uid: "guest",
        roleId: `${WS}_owner`, status: "active",
      }),
    );
  });
});

describe("owner guardrails", () => {
  it("the owner's membership cannot be deleted while the workspace exists", async () => {
    const db = env.authenticatedContext("owner").firestore();
    await assertFails(
      // even owner has members.remove, but owner row is protected
      deleteDoc(doc(db, "memberships", `${WS}_owner`)),
    );
  });

  it("the owner CAN delete their dangling membership once the workspace is gone", async () => {
    // Deleting a workspace removes the workspace doc first, then the owner's
    // own membership; this verifies the post-delete cleanup is permitted.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), "workspaces", WS));
    });
    const db = env.authenticatedContext("owner").firestore();
    await assertSucceeds(deleteDoc(doc(db, "memberships", `${WS}_owner`)));
  });

  it("the owner can delete their own workspace", async () => {
    const db = env.authenticatedContext("owner").firestore();
    await assertSucceeds(deleteDoc(doc(db, "workspaces", WS)));
  });

  it("the owner can remove another member (workspace-delete cleanup)", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "memberships", `${WS}_other`), {
        id: `${WS}_other`,
        workspaceId: WS,
        uid: "other",
        roleId: `${WS}_owner`,
        status: "active",
      });
    });
    const db = env.authenticatedContext("owner").firestore();
    await assertSucceeds(deleteDoc(doc(db, "memberships", `${WS}_other`)));
  });
});

// =============================================================================
// Cross-user shared ledger: sharedConnections / shareInvites / sharedEntries.
// These are gated by "are you one of the two parties", NOT by workspace.
// =============================================================================

describe("shared ledger — connections & entries", () => {
  const A = "userA";
  const B = "userB";
  const C = "stranger3";
  const CONN = "userA_userB"; // sorted pair

  async function seedConnection() {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "sharedConnections", CONN), {
        id: CONN,
        uids: [A, B],
        names: { [A]: "A", [B]: "B" },
        emails: { [A]: "a@x.com", [B]: "b@x.com" },
        status: "active",
      });
    });
  }

  function entryDoc(over: Record<string, unknown> = {}) {
    return {
      id: "e1",
      connectionId: CONN,
      kind: "expense",
      uids: [A, B],
      creatorUid: A,
      counterpartyUid: B,
      names: { [A]: "A", [B]: "B" },
      payerUid: A,
      description: "Dinner",
      amount: 100,
      date: new Date(),
      status: "pending",
      pendingForUids: [B],
      createdBy: { uid: A, name: "A" },
      ...over,
    };
  }

  it("a party can read the connection; a stranger cannot", async () => {
    await seedConnection();
    await assertSucceeds(getDoc(doc(env.authenticatedContext(A).firestore(), "sharedConnections", CONN)));
    await assertFails(getDoc(doc(env.authenticatedContext(C).firestore(), "sharedConnections", CONN)));
  });

  it("the creator can create a bilateral entry they are part of", async () => {
    const db = env.authenticatedContext(A).firestore();
    await assertSucceeds(setDoc(doc(db, "sharedEntries", "e1"), entryDoc()));
  });

  it("a stranger cannot create an entry naming two other users", async () => {
    const db = env.authenticatedContext(C).firestore();
    await assertFails(setDoc(doc(db, "sharedEntries", "e1"), entryDoc()));
  });

  it("you cannot create an entry claiming someone else is the creator", async () => {
    const db = env.authenticatedContext(B).firestore();
    await assertFails(
      setDoc(doc(db, "sharedEntries", "e1"), entryDoc({ createdBy: { uid: A, name: "A" } })),
    );
  });

  it("the counterparty may flip ONLY their consent", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "sharedEntries", "e1"), entryDoc());
    });
    const db = env.authenticatedContext(B).firestore();
    await assertSucceeds(
      updateDoc(doc(db, "sharedEntries", "e1"), { status: "accepted", pendingForUids: [] }),
    );
  });

  it("the counterparty cannot change the amount", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "sharedEntries", "e1"), entryDoc());
    });
    const db = env.authenticatedContext(B).firestore();
    await assertFails(updateDoc(doc(db, "sharedEntries", "e1"), { amount: 1 }));
  });

  it("the creator cannot change their own consent fields, only `resolved`", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "sharedEntries", "e1"), entryDoc({ status: "rejected" }));
    });
    const db = env.authenticatedContext(A).firestore();
    await assertFails(updateDoc(doc(db, "sharedEntries", "e1"), { status: "accepted" }));
    await assertSucceeds(updateDoc(doc(db, "sharedEntries", "e1"), { resolved: true }));
  });

  it("a stranger cannot read someone else's entry", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "sharedEntries", "e1"), entryDoc());
    });
    await assertFails(getDoc(doc(env.authenticatedContext(C).firestore(), "sharedEntries", "e1")));
  });

  it("only the creator can delete an entry", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "sharedEntries", "e1"), entryDoc());
    });
    await assertFails(deleteDoc(doc(env.authenticatedContext(B).firestore(), "sharedEntries", "e1")));
    await assertSucceeds(deleteDoc(doc(env.authenticatedContext(A).firestore(), "sharedEntries", "e1")));
  });
});

describe("shared ledger — invites", () => {
  const A = "inviterA";
  it("the inviter can create a deterministic-id invite for themselves", async () => {
    const db = env.authenticatedContext(A, { email: "a@x.com" }).firestore();
    await assertSucceeds(
      setDoc(doc(db, "shareInvites", `${A}_guest@x.com`), {
        id: `${A}_guest@x.com`,
        fromUid: A,
        fromName: "A",
        fromEmail: "a@x.com",
        toEmail: "guest@x.com",
        status: "pending",
      }),
    );
  });

  it("you cannot forge an invite from another user", async () => {
    const db = env.authenticatedContext("someoneElse", { email: "e@x.com" }).firestore();
    await assertFails(
      setDoc(doc(db, "shareInvites", `${A}_guest@x.com`), {
        id: `${A}_guest@x.com`,
        fromUid: A,
        fromName: "A",
        fromEmail: "a@x.com",
        toEmail: "guest@x.com",
        status: "pending",
      }),
    );
  });

  it("the invitee (by email) may flip only the status to accepted", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "shareInvites", `${A}_guest@x.com`), {
        id: `${A}_guest@x.com`,
        fromUid: A,
        fromName: "A",
        fromEmail: "a@x.com",
        toEmail: "guest@x.com",
        status: "pending",
      });
    });
    const db = env.authenticatedContext("guest", { email: "guest@x.com" }).firestore();
    await assertSucceeds(updateDoc(doc(db, "shareInvites", `${A}_guest@x.com`), { status: "accepted" }));
  });
});
