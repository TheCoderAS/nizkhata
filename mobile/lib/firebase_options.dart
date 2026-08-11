// Firebase configuration for the native Android app.
//
// Values are injected at build time via --dart-define (wired to GitHub Actions
// secrets in .github/workflows/android-apk.yml), so no secrets live in the repo.
// These are the SAME public client-config values the web app reads from its
// VITE_FIREBASE_* env — apiKey/appId/etc. are client identifiers, not secrets,
// but we still keep them out of source.
//
// `googleWebClientId` is the OAuth 2.0 *Web* client ID from the Firebase project
// (Authentication → Google). google_sign_in uses it as the ID-token audience so
// firebase_auth accepts the credential. The Android app's package name + signing
// SHA-1 must also be registered as an Android OAuth client in Google Cloud, or
// native Google sign-in returns null. See mobile/README.md.

import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  // Web OAuth 2.0 client ID (client_type 3 in google-services.json). Used as the
  // ID-token audience for native google_sign_in so firebase_auth accepts the
  // credential. Public identifier — safe to bake in.
  static const String googleWebClientId =
      '626552427608-uhi017lm6gph5ug2c3aq3v7tbh0c1576.apps.googleusercontent.com';

  // Native Android config for project `nizkhata` (from google-services.json).
  // All PUBLIC identifiers — security lives in Firestore Rules + the OAuth
  // client's package-name/SHA-1 lock, not in hiding these. So the app is fully
  // configured with zero secrets.
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: 'AIzaSyBUNKeUYJ_3M8u3h4IJER7eflq2C8kd-AU',
    appId: '1:626552427608:android:0375a1216b3f0a6906a62d',
    messagingSenderId: '626552427608',
    projectId: 'nizkhata',
    authDomain: 'nizkhata.firebaseapp.com',
    storageBucket: 'nizkhata.firebasestorage.app',
  );
}
