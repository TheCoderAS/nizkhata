// Login screen (§6.1) — Google sign-in.

import { Navigate } from "react-router-dom";
import { useAuth } from "@/auth/AuthProvider";
import { ErrorState, LoadingState } from "@/components/states";

export function Login() {
  const { firebaseUser, loading, error, signIn } = useAuth();

  if (loading) return <LoadingState label="Loading…" />;
  if (firebaseUser) return <Navigate to="/" replace />;

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-6 bg-gray-50">
      <div className="text-center">
        <h1 className="text-2xl font-semibold">Shared Accounting</h1>
        <p className="text-gray-500">Multi-workspace, shared books.</p>
      </div>
      <button
        onClick={() => void signIn()}
        className="rounded-md bg-gray-900 px-5 py-2.5 text-white hover:bg-gray-700"
      >
        Continue with Google
      </button>
      {error && (
        <div className="w-full max-w-sm">
          <ErrorState message={error} />
        </div>
      )}
    </div>
  );
}
