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
  static const String googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '');

  // Firebase Web client config for project `nizkhata`. These are PUBLIC
  // identifiers (they ship in the web app's JS bundle — see the web deploy
  // workflow), so they're safe to bake in; security lives in Firestore Rules.
  // Baking them in means the app is correctly configured with zero secrets.
  static FirebaseOptions get currentPlatform => const FirebaseOptions(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY',
            defaultValue: 'AIzaSyAiCtL1MqHDuzpNvCRGIpnuEY1vJTHN03I'),
        appId: String.fromEnvironment('FIREBASE_APP_ID',
            defaultValue: '1:626552427608:web:de49ec934a647fce06a62d'),
        messagingSenderId:
            String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '626552427608'),
        projectId:
            String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'nizkhata'),
        authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN',
            defaultValue: 'nizkhata.firebaseapp.com'),
        storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET',
            defaultValue: 'nizkhata.firebasestorage.app'),
        measurementId:
            String.fromEnvironment('FIREBASE_MEASUREMENT_ID', defaultValue: 'G-N6JH009E7Q'),
      );
}
