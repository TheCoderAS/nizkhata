// App shell: top bar (user + sign out) + sidebar + routed content (§6).

import { Outlet } from "react-router-dom";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { Sidebar } from "./Sidebar";
import { ErrorState, LoadingState } from "./states";

export function AppShell() {
  const { firebaseUser, signOut } = useAuth();
  const { loading, error, memberships } = useWorkspace();

  if (loading) return <LoadingState label="Loading workspace…" />;
  if (error) return <ErrorState message={error} />;

  return (
    <div className="flex h-screen flex-col">
      <header className="flex items-center justify-between border-b border-gray-200 px-4 py-2">
        <span className="font-semibold">Shared Accounting</span>
        <div className="flex items-center gap-3 text-sm">
          <span className="text-gray-600">{firebaseUser?.email}</span>
          <button
            onClick={() => void signOut()}
            className="rounded-md border border-gray-300 px-3 py-1 hover:bg-gray-100"
          >
            Sign out
          </button>
        </div>
      </header>
      <div className="flex min-h-0 flex-1">
        {memberships.length > 0 && <Sidebar />}
        <main className="min-w-0 flex-1 overflow-auto p-6">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
