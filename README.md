# Shared Accounting App

Multi-workspace, single-entry accounting with multi-line transactions, contacts,
debts, dues, transfers, and per-line tax tagging.

**Stack:** React + Vite + TypeScript · Firebase (Firestore + Google Auth) ·
Firestore Security Rules · Tailwind CSS. Pure client + Firestore + Rules (no
Cloud Functions).

> Status: **Foundation phase** (build-order steps 1–4) is implemented — data
> model, seed logic, Security Rules + tests, auth, onboarding, workspace +
> permission context, and a permission-gated app shell. Feature screens
> (Accounts → Reports, Members/Roles editors, CSV) are scaffolded as gated
> placeholders. See `SPEC_NOTES.md` for design decisions, deviations from the
> spec, and open questions.

## Getting started

```bash
npm install
cp .env.example .env     # fill in your Firebase web config
```

### Run against the local emulator (recommended for dev)

Requires the [Firebase CLI](https://firebase.google.com/docs/cli) and Java
(for the Firestore emulator).

```bash
# .env: VITE_USE_EMULATORS=true
npm run emulators        # starts Auth + Firestore + Emulator UI (port 4000)
npm run dev              # in another terminal
```

### Run against a real Firebase project

1. Create a Firebase project; enable **Google** sign-in and **Cloud Firestore**.
2. Put the web app config into `.env` and set `VITE_USE_EMULATORS=false`.
3. Deploy rules + indexes: `npm run deploy:rules`.

### Deploy (Firebase Hosting)

The app is hosted on Firebase Hosting — same platform as Auth + Firestore, so
the app, Security Rules and indexes deploy together with one command.

```bash
firebase login            # once
npm run deploy            # build + deploy hosting, rules and indexes
# or target one thing:
npm run deploy:hosting    # build + deploy only the static site
npm run deploy:rules      # deploy only firestore rules + indexes
```

`.firebaserc` already points at the `nizkhata` project. The `dist` build reads
`VITE_FIREBASE_*` from your local `.env` at build time.

## Scripts

| Script | What |
|---|---|
| `npm run dev` | Vite dev server |
| `npm run build` | typecheck + production build |
| `npm run typecheck` | `tsc` only |
| `npm test` / `npx vitest run` | pure-logic unit tests (FY + transaction engine) |
| `npm run test:rules` | Security Rules matrix (needs emulator + Java) |
| `npm run emulators` | Firebase Emulator Suite |
| `npm run deploy` | build + deploy hosting, rules and indexes |
| `npm run deploy:hosting` | build + deploy only the static site |
| `npm run deploy:rules` | deploy only Firestore rules + indexes |

Run the rules tests with the emulator wrapper:

```bash
firebase emulators:exec --only firestore "npm run test:rules"
```

## Architecture

```
src/
  types/         models.ts (Firestore schema) · permissions.ts (catalog + system roles)
  lib/           txn.ts (balance math + validation engine) · financialYear.ts
  firebase/      config.ts (app init + emulator wiring)
  auth/          AuthProvider (Google sign-in + first-login onboarding)
  workspace/     WorkspaceProvider (memberships, active workspace, can()) ·
                 onboarding.ts (invite claim / personal-workspace seed) · seed.ts
  components/    AppShell · Sidebar · ProtectedRoute · states (loading/empty/error/no-perm)
  pages/         Login · Dashboard · gated placeholders
firestore.rules          Security Rules (the real isolation boundary)
firestore.indexes.json   composite indexes (§9)
test/rules/              Security Rules test matrix
```

**Derived-not-stored:** account balances, debt outstanding, contact positions,
due remaining, and tax totals are all computed from transaction lines via
`src/lib/txn.ts` — never persisted (avoids drift).
