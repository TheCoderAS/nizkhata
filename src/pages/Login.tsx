// Login screen (§6.1) — Google sign-in. Modern split layout, theme-aware,
// animated entrance.

import { Navigate } from "react-router-dom";
import { useAuth } from "@/auth/AuthProvider";
import { ErrorState, LoadingState } from "@/components/states";
import { Button } from "@/components/ui/button";
import { ThemeToggle } from "@/components/ThemeToggle";

function GoogleIcon() {
  return (
    <svg className="h-4 w-4" viewBox="0 0 24 24" aria-hidden="true">
      <path
        fill="#4285F4"
        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.27-4.74 3.27-8.1Z"
      />
      <path
        fill="#34A853"
        d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.99.66-2.26 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84A11 11 0 0 0 12 23Z"
      />
      <path
        fill="#FBBC05"
        d="M5.84 14.1a6.6 6.6 0 0 1 0-4.2V7.06H2.18a11 11 0 0 0 0 9.88l3.66-2.84Z"
      />
      <path
        fill="#EA4335"
        d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1A11 11 0 0 0 2.18 7.06l3.66 2.84C6.71 7.3 9.14 5.38 12 5.38Z"
      />
    </svg>
  );
}

export function Login() {
  const { firebaseUser, loading, error, signIn } = useAuth();

  if (loading) return <LoadingState label="Loading…" />;
  if (firebaseUser) return <Navigate to="/" replace />;

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-background p-4">
      {/* ambient gradient blobs */}
      <div className="pointer-events-none absolute -left-24 -top-24 h-72 w-72 rounded-full bg-primary/20 blur-3xl" />
      <div className="pointer-events-none absolute -bottom-24 -right-24 h-72 w-72 rounded-full bg-primary/10 blur-3xl" />

      <div className="absolute right-4 top-4">
        <ThemeToggle />
      </div>

      <div className="w-full max-w-sm animate-fade-in-up rounded-2xl border bg-card p-8 shadow-xl">
        <div className="mb-6 flex flex-col items-center text-center">
          <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary text-2xl font-bold text-primary-foreground shadow-lg">
            ₹
          </div>
          <h1 className="text-2xl font-semibold tracking-tight">Nizkhata</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Multi-workspace shared accounting.
          </p>
        </div>

        <Button
          size="lg"
          variant="outline"
          className="w-full gap-2"
          onClick={() => void signIn()}
        >
          <GoogleIcon />
          Continue with Google
        </Button>

        {error && (
          <div className="mt-4">
            <ErrorState message={error} />
          </div>
        )}

        <p className="mt-6 text-center text-xs text-muted-foreground">
          Your first sign-in creates a personal workspace automatically.
        </p>
      </div>
    </div>
  );
}
