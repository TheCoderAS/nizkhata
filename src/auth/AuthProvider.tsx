// Auth context: tracks the Firebase user, exposes sign-in/sign-out, and ensures
// a `users/{uid}` doc + onboarding (invite claim or personal workspace) on first
// login (§5).

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
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

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (user) => {
      try {
        setError(null);
        setCurrentActor(actorFromUser(user));
        if (user) {
          await ensureUserAndOnboarding(user);
        }
        setFirebaseUser(user);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Sign-in failed.");
      } finally {
        setLoading(false);
      }
    });
    return unsub;
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
