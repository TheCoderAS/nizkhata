// Firebase app initialization. Reads config from Vite env vars (see .env.example).
// When VITE_USE_EMULATORS=true, connects Auth + Firestore to the local Emulator
// Suite instead of a real project (build order step 1).

import { initializeApp, type FirebaseOptions } from "firebase/app";
import {
  initializeAuth,
  indexedDBLocalPersistence,
  browserLocalPersistence,
  browserPopupRedirectResolver,
  connectAuthEmulator,
  GoogleAuthProvider,
} from "firebase/auth";
import {
  initializeFirestore,
  persistentLocalCache,
  persistentMultipleTabManager,
  connectFirestoreEmulator,
} from "firebase/firestore";

const firebaseConfig: FirebaseOptions = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
  measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID,
};

export const app = initializeApp(firebaseConfig);

// Pin an explicit, durable persistence chain instead of getAuth()'s lazy
// default. IndexedDB survives PWA cold-starts (e.g. iOS "Add to Home Screen"
// standalone) reliably; localStorage is the fallback when IndexedDB is
// unavailable. Without this, the session often fails to restore when the PWA
// is backgrounded and reopened, bouncing the user to the sign-in screen.
// `browserPopupRedirectResolver` is required because we sign in via popup.
export const auth = initializeAuth(app, {
  persistence: [indexedDBLocalPersistence, browserLocalPersistence],
  popupRedirectResolver: browserPopupRedirectResolver,
});
// Enable IndexedDB-backed offline persistence so the app loads instantly from
// cache and queues writes while offline (important for a PWA used on flaky
// mobile networks). The multi-tab manager keeps the cache coherent across the
// multiple tabs this app explicitly supports. Must use initializeFirestore
// (not getFirestore) so the cache is configured before any other Firestore use.
export const db = initializeFirestore(app, {
  localCache: persistentLocalCache({ tabManager: persistentMultipleTabManager() }),
});
export const googleProvider = new GoogleAuthProvider();

const useEmulators = import.meta.env.VITE_USE_EMULATORS === "true";

if (useEmulators) {
  // Guard against double-connecting during HMR.
  // @ts-expect-error internal flag we set ourselves
  if (!globalThis.__EMULATORS_CONNECTED__) {
    connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
    connectFirestoreEmulator(db, "127.0.0.1", 8080);
    // @ts-expect-error internal flag we set ourselves
    globalThis.__EMULATORS_CONNECTED__ = true;
    // eslint-disable-next-line no-console
    console.info("[firebase] connected to local emulators");
  }
} else if (import.meta.env.PROD && import.meta.env.VITE_FIREBASE_MEASUREMENT_ID) {
  // Analytics only in production builds against the real project, and only if
  // the browser supports it (avoids SSR/unsupported-environment errors).
  void import("firebase/analytics").then(({ getAnalytics, isSupported }) =>
    isSupported().then((ok) => {
      if (ok) getAnalytics(app);
    }),
  );
}
