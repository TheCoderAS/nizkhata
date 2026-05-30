// The four states every screen must handle (§6): loading, empty, error,
// no-permission. Small presentational helpers reused across pages.

import type { ReactNode } from "react";

export function LoadingState({ label = "Loading…" }: { label?: string }) {
  return (
    <div className="flex items-center justify-center p-12 text-gray-500">
      <span className="animate-pulse">{label}</span>
    </div>
  );
}

export function EmptyState({
  title,
  hint,
  action,
}: {
  title: string;
  hint?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 p-12 text-center">
      <p className="text-gray-700 font-medium">{title}</p>
      {hint && <p className="text-sm text-gray-500">{hint}</p>}
      {action && <div className="mt-2">{action}</div>}
    </div>
  );
}

export function ErrorState({ message }: { message: string }) {
  return (
    <div className="m-6 rounded-md border border-red-200 bg-red-50 p-4 text-red-700">
      <p className="font-medium">Something went wrong</p>
      <p className="text-sm">{message}</p>
    </div>
  );
}

export function NoPermissionState({ perm }: { perm?: string }) {
  return (
    <div className="m-6 rounded-md border border-amber-200 bg-amber-50 p-4 text-amber-800">
      <p className="font-medium">You don't have access to this</p>
      <p className="text-sm">
        Ask a workspace admin for the
        {perm ? <code className="mx-1 rounded bg-amber-100 px-1">{perm}</code> : " required "}
        permission.
      </p>
    </div>
  );
}
