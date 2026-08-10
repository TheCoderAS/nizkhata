# NizKhata — Native Android app (Flutter)

A **pure native** Flutter port of the NizKhata web app. It talks to the **same
Firebase project (`nizkhata`)** — the same Firestore data, the same auth — via
the native `firebase_auth` / `cloud_firestore` / `google_sign_in` SDKs. No
WebView, no PWA wrapper. Domain models, derivations (balances, net worth, debt
outstanding, dues, contact position, budgets), permissions and seed data are
Dart re-implementations of the web `src/` and match its formulas 1:1
(see `PORT_SPEC.md`).

**Minimum supported OS: Android 12 (API 31).**

## Getting the APK

The APK is built by **GitHub Actions** (`.github/workflows/android-apk.yml`):

- **On demand:** Actions → *Android APK* → *Run workflow* → download the
  `nizkhata-apk` artifact.
- **On a version tag:** push a tag `vX.Y.Z` and the APK is attached to the
  GitHub Release automatically.

The workflow builds without any secrets (so you always get an installable APK),
but **Google sign-in and Firestore need the configuration below** to work at
runtime.

## One-time Firebase / Google Cloud setup (required for sign-in)

This is standard Firebase-Android setup — nothing in the code can do it for you,
because it registers *this app* with your Google project.

1. **Register the Android app** in the Firebase console (project `nizkhata`):
   - Package name: **`com.nizkhata.nizkhata`**
   - Add the signing certificate **SHA-1** (see below).
2. **Add repo secrets** (Settings → Secrets and variables → Actions). The Firebase
   ones are the **same `VITE_FIREBASE_*` secrets the web app already uses** — the
   workflow reads them directly, so you don't configure Firebase twice:
   - `VITE_FIREBASE_API_KEY`
   - `VITE_FIREBASE_APP_ID`
   - `VITE_FIREBASE_MESSAGING_SENDER_ID`
   - `VITE_FIREBASE_PROJECT_ID` (`nizkhata`)
   - `VITE_FIREBASE_AUTH_DOMAIN` (`nizkhata.firebaseapp.com`)
   - `VITE_FIREBASE_STORAGE_BUCKET`
   - `VITE_FIREBASE_MEASUREMENT_ID`

   The only **Android-specific** secret to add:
   - `GOOGLE_WEB_CLIENT_ID` — the **Web** OAuth 2.0 client ID from
     *Authentication → Sign-in method → Google* (used as the ID-token audience so
     Firebase accepts the native Google credential). The web app didn't need this
     because its popup sign-in uses `authDomain`.
   - *(optional)* `GOOGLE_SERVICES_JSON_BASE64` — `base64 -w0 google-services.json`
     if you prefer to ship it instead of the individual values.
3. **Register the SHA-1.** A release keystore is already generated and the
   workflow signs release APKs with it (when the secrets below are present), so
   the SHA-1 is **stable**. Register this fingerprint on the
   `com.nizkhata.nizkhata` Android app in the Firebase console:
   ```
   SHA-1:   9D:29:33:32:2F:6D:22:E7:48:70:1C:D8:5E:12:60:CD:6F:C5:84:83
   SHA-256: 87:B6:66:C1:A5:E1:A6:7A:28:7D:F2:18:02:A5:87:00:2F:FC:53:B4:98:2C:F5:9D:27:A0:A6:09:B0:CF:D9:62
   ```
   Add these signing secrets (the keystore file + passwords were provided
   separately — store them safely, they sign your releases):
   - `ANDROID_KEYSTORE_BASE64` — base64 of `nizkhata-release.jks`
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEY_PASSWORD`
   - `ANDROID_KEY_ALIAS` (`nizkhata`)

   Without these secrets the build falls back to debug signing (installable, but
   its SHA-1 is ephemeral so Google sign-in won't match).

Firestore Security Rules are already deployed for the web app and apply
unchanged (same project), so no rules changes are needed.

## Local development

```
cd mobile
flutter create --platforms=android --org com.nizkhata --project-name nizkhata .
git checkout -- lib pubspec.yaml          # keep our sources
flutter pub get
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=... --dart-define=FIREBASE_API_KEY=... [etc]
```

## Architecture

```
lib/
  main.dart                 Firebase init + providers + MaterialApp.router
  router.dart               go_router (+ auth redirect), bottom-nav shell
  firebase_options.dart     FirebaseOptions from --dart-define
  core/theme.dart           Material 3 brand theme (indigo/emerald, light+dark)
  core/format.dart          formatMoney / formatDate / avatars (ports utils.ts)
  data/models.dart          Firestore <-> Dart models (ports types/models.ts)
  data/permissions.dart     permission catalog + role templates + seed data
  data/derive.dart          txn engine + all derivations (ports txn/derive/period/FY)
  state/auth_controller.dart      Google sign-in + first-login onboarding
  state/workspace_controller.dart memberships/roles/active workspace + can()
  state/data_controller.dart      live Firestore streams + derived lookups
  screens/                  login, shell, dashboard, transactions, dues, debts,
                            contacts, more
  widgets/common.dart       StatCard, EntityAvatar, section/empty/loading
```

State management mirrors the web React context providers
(Auth → Workspace → Data) via `provider`.

## Port status

This is being ported screen-by-screen and validated through the APK CI. Current
coverage:

- ✅ Google sign-in (native) + first-login onboarding (user doc, personal
  workspace seed: 4 system roles + 18 default categories, `lastWorkspaceId`)
- ✅ Workspace context + RBAC `can(permission)` + workspace switching
- ✅ Live Firestore streams for all workspace collections
- ✅ Derivations ported 1:1 (balances, net worth, debt outstanding, dues
  settlement/status, custodial, contact position, spend-by-category, trend,
  budgets, FY/period)
- ✅ Dashboard (net-worth hero + sparkline, income/expense/net, balances,
  spend-by-category, recent transactions, period selector)
- ✅ Transactions / Dues / Debts / Contacts list views + summaries
- ✅ More (profile, workspace stats, switch workspace, sign out)
- ⏳ Create/edit forms (transactions, dues, debts, contacts, accounts,
  categories, budgets)
- ⏳ Contact detail, Reports/Insights (+ CSV export), Settings sub-pages
  (accounts/ledger, categories, budgets, members, roles, workspace)
- ⏳ Shared ledger (cross-user), Activity feed

Each new screen lands behind the same CI so the APK stays buildable.
