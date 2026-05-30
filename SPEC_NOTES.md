# Spec Review — Questions, Doubts & Deviations

This captures my read of `buildspec.md`: where I deviated, what I had to decide,
and the open questions that need your call before later phases. The spec is
strong overall — the requirement→design map, the line-type→balance-effect table,
and the build order are all coherent. The notes below are the friction points.

## Deviations already made (implemented this way)

### 1. Security Rules: closed a membership self-join privilege-escalation hole — **needs confirmation**
The spec's draft rule allows `memberships` create when
`request.resource.data.uid == request.auth.uid`. As written, **any signed-in
user can mint a membership in any workspace with any roleId** — e.g. assign
themselves that workspace's Owner role and read/write the whole book. That
breaks the data-isolation boundary the spec calls the core of the app.

**Fix implemented.** Membership create now requires one of:
- caller has `members.invite`, or
- caller is the workspace owner (bootstrap), or
- a **matching pending invite** exists for the caller's email whose `roleId`
  equals the membership being created.

Because Rules can only `get()` a known doc id (not query), this required making
**invite doc IDs deterministic**: `invites/{workspaceId}_{lowercased-email}`
instead of the spec's random id. **Open question:** OK to adopt deterministic
invite IDs? Trade-off: only one outstanding invite per email per workspace
(re-inviting overwrites). The alternative that preserves random ids is a Cloud
Function to mint memberships — but the spec forbids Functions in v1.

### 2. Security Rules: bootstrap chicken-and-egg on first login
Seeding the 4 system roles + owner membership + default categories needs
`roles.manage`/`categories.manage` perms that don't exist yet at first login.
I added an **owner bypass**: the workspace owner may create roles/memberships/
categories directly. For this to work the client creates the `workspaces/{ws}`
doc as its own committed write **first**, then seeds the rest in a batch (so
`get(workspace).ownerId` resolves). Implemented in `onboarding.ts`.

### 3. Hardening added beyond the spec draft
- `workspaceId` is immutable on update across all collections (no moving a doc
  between books).
- `transactions` update can't change `createdBy`; `workspaces` update can't
  change `ownerId` (already in spec).
- Owner's membership can't be deleted *or* role-changed (spec only said
  delete).
- A catch-all `match /{document=**} { allow read, write: if false; }` default-deny.
- `categories` delete blocked for `isSystem` categories (spec marks them
  read-only in the UI but the draft rules didn't enforce it).

### 4. Tech-stack picks (spec left these open)
Vite + TypeScript + Tailwind, React Router, Firebase JS SDK v10. `baseCurrency`
defaults to `INR`, `fyStartMonth` to `4` on auto-created workspaces.

## Things enforced in app logic only (not expressible in Rules)
The spec acknowledges some of these; listing for completeness. These are **not
yet implemented** (they belong to the Members/Roles phase):
- Cannot delete a role still assigned to a membership.
- Cannot remove the last holder of `roles.manage` / `members.remove`.
- `totalAmount == signed sum of lines` — Rules can't cheaply sum the `lines`
  array, so this is validated client-side (`src/lib/txn.ts`) and is covered by
  unit tests. If you want server-side guarantee, it needs a Function.

## Open questions for later phases

1. **Invite IDs** — confirm the deterministic-id deviation above (or accept a
   Cloud Function, which contradicts the "no Functions" constraint).
2. **`tax` line sign "by context"** — the spec says default `−` but "sign by
   context". Right now `tax` always debits. What's the rule for when a tax line
   should *credit* (refund of tax)? A separate line type, or a signed flag?
3. **`repayment` direction source of truth** — I resolve a repayment's sign from
   the linked `debt.direction`. Confirm a repayment line is always tied to
   exactly one debt (the validation assumes this).
4. **Dashboard "Held for others (custodial)"** — is this the sum of outstanding
   on debts with `purpose: custodial_savings` (direction `owe`)? Confirming the
   exact derivation before building Reports.
5. **FY label format for non-April starts** — for `fyStartMonth = 1` (Jan) I emit
   a single-year label (`"2025"`); for April etc. I emit `"2025-26"`. OK?
6. **Multi-currency** — `baseCurrency` exists per workspace but the model has no
   per-transaction currency. Assuming single-currency per workspace for v1?
7. **Account deletion vs. history** — Rules allow `accounts.manage` to delete an
   account, but transactions reference `accountId`. Soft-delete/archive, or
   block deletion when referenced? (Same question for categories/contacts/debts.)
8. **`workspaces` "in" query** — the live workspace loader uses Firestore `in`
   (max 30 ids). Fine for v1 membership counts; flag if you expect users in 30+
   workspaces.

## Environment limitation in this build session
This container has **no Firebase CLI and no Java**, so I could not *run* the
emulator or the Security Rules test matrix here. The rules tests are written
(`test/rules/firestore.rules.test.ts`) and the pure-logic unit tests (26, all
passing) run without the emulator. Please run
`firebase emulators:exec --only firestore "npm run test:rules"` locally to
validate the full rules matrix before relying on it.
```
