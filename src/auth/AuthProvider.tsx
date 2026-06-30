// Auth context: tracks the Firebase user, exposes sign-in/sign-out, and ensures
// a `users/{uid}` doc + onboarding (invite claim or personal workspace) on first
// login (§5).

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import {
  onAuthStateChanged,
  signInWithPopup,
  signOut as fbSignOut,
  type User as FirebaseUser,
} from "firebase/auth";
import { auth, googleProvider } from "@/firebase/config";
import { ensureUserAndOnboarding } from "@/workspace/onboarding";
import { actorFromUser, setCurrentActor } from "@/data/actor";

interface AuthState {
  firebaseUser: FirebaseUser | null;
  loading: boolean;
  error: string | null;
  signIn: () => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthState | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [firebaseUser, setFirebaseUser] = useState<FirebaseUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  // uid we've already kicked off onboarding for this session, so resumes don't
  // re-run the (idempotent) onboarding chain redundantly.
  const ensuredUid = useRef<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const unsub = onAuthStateChanged(auth, (user) => {
      if (cancelled) return;
      setError(null);
      setCurrentActor(actorFromUser(user));
      // Resolve the UI from the (persisted) auth state immediately. Onboarding
      // is a long chain of Firestore round-trips and is only meaningful on
      // first login, so we must NOT block the "Signing in…" gate behind it —
      // otherwise every cold PWA resume re-shows the loader for its duration.
      setFirebaseUser(user);
      setLoading(false);

      if (user && ensuredUid.current !== user.uid) {
        ensuredUid.current = user.uid;
        // Run in the background; WorkspaceProvider listens to memberships live,
        // so any docs onboarding creates appear as soon as they're written.
        ensureUserAndOnboarding(user).catch((e) => {
          ensuredUid.current = null; // allow a retry on the next auth event
          if (!cancelled) setError(e instanceof Error ? e.message : "Sign-in failed.");
        });
      } else if (!user) {
        ensuredUid.current = null;
      }
    });
    return () => {
      cancelled = true;
      unsub();
    };
  }, []);

  const value = useMemo<AuthState>(
    () => ({
      firebaseUser,
      loading,
      error,
      async signIn() {
        setError(null);
        try {
          await signInWithPopup(auth, googleProvider);
        } catch (e) {
          setError(e instanceof Error ? e.message : "Sign-in failed.");
          throw e;
        }
      },
      async signOut() {
        await fbSignOut(auth);
      },
    }),
    [firebaseUser, loading, error],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within <AuthProvider>");
  return ctx;
}
