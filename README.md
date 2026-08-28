# NizKhata

**Every rupee, accounted for.**

A shared money ledger for Android: multi-workspace, single-entry accounting
with multi-line transactions, contacts, debts, dues, transfers, per-line tax
tagging, role-based access control, and on-device bank-statement import
(CSV / Excel / PDF — including password-protected files).

**The product is the native Android app** (`mobile/`, Flutter). The former
React web app has been retired; https://nizkhata.web.app now serves a static
landing page (`landing/`) that links the latest APK, and continues to host
`/.well-known/assetlinks.json` for Android App Links.

**Stack:** Flutter (Android) · Firebase (Firestore + Google Auth) · Firestore
Security Rules. Pure client + Firestore + Rules — no Cloud Functions, no
servers.

## Repository layout

```
mobile/                  The Android app (Flutter). Everything user-facing.
  lib/services/          statement parsing (CSV/XLSX/XLS/PDF), Office & PDF
                         decryption, reminders, widget sync, secure storage
  test/                  parser/crypto/import unit tests + real-file fixtures
landing/                 Static landing page served at nizkhata.web.app
firestore.rules          Security Rules (the real isolation boundary)
firestore.indexes.json   Composite indexes
test/rules/              Security Rules test matrix (runs against the emulator)
.github/workflows/
  android-apk.yml        Builds, signs and releases the APK (workflow_dispatch
                         with a version input publishes vX.Y.Z)
  ci.yml                 PR gate: landing-page validation + rules tests
  deploy.yml             Deploys hosting + rules + indexes on merge to main
```

## Android app

```bash
cd mobile
flutter pub get
flutter analyze          # 0 errors expected
flutter test             # parser / crypto / import suites
```

Releases are built by CI (`android-apk.yml`): the Android platform scaffold is
generated fresh with `flutter create` each build and patched (permissions,
App Links, widget/receiver injection, signing, compileSdk overrides) — the
`android/` directory is deliberately untracked. Dispatch the workflow with a
`version` input (e.g. `v1.0.28`) to publish a tagged GitHub release; the
landing page always links the latest.

## Security Rules

Rules are shared by every client and tested against the emulator:

```bash
npm ci
npx firebase-tools emulators:exec --only firestore --project demo-rules-test "npm run test:rules"
```

**Derived-not-stored:** account balances, debt outstanding, contact positions,
due remaining, and tax totals are all computed from transaction lines on the
client — never persisted (avoids drift).

## Deploy

Merging to main auto-deploys hosting (landing page) + rules + indexes via
`deploy.yml`. Manually: `npm run deploy` (needs the Firebase CLI and project
access).
