// The four states every screen must handle (§6): loading, empty, error,
// no-permission. Token-based colors so they adapt to light/dark.

import type { ReactNode } from "react";
import { AlertCircle, Inbox, Lock, Loader2 } from "lucide-react";
import logoUrl from "@/assets/logo.png";

export function LoadingState({ label = "Loading…" }: { label?: string }) {
  return (
    <div className="flex items-center justify-center gap-2 p-12 text-muted-foreground">
      <Loader2 className="h-4 w-4 animate-spin" />
      <span>{label}</span>
    </div>
  );
}

/**
 * Branded full-screen boot splash. Used while auth/workspace state resolves on
 * app entry, so the first paint is the brand — not a blank screen or a bare
 * spinner.
 */
export function FullScreenLoader({ label }: { label?: string }) {
  return (
    <div className="fixed inset-0 z-50 flex flex-col items-center justify-center gap-5 bg-background">
      <img
        src={logoUrl}
        alt="NizKhata"
        className="h-16 w-16 animate-pulse rounded-2xl shadow-lg"
      />
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <Loader2 className="h-4 w-4 animate-spin" />
        <span>{label ?? "Loading…"}</span>
      </div>
    </div>
  );
}

/**
 * Lightweight page placeholder shown while a lazily-loaded route chunk arrives.
 * Mimics a page header + a few rows so navigation feels instant.
 */
export function PageSkeleton() {
  return (
    <div className="animate-fade-in space-y-6">
      <div className="flex items-center justify-between">
        <Skeleton className="h-8 w-40" />
        <Skeleton className="h-9 w-28" />
      </div>
      <Skeleton className="h-10 w-full" />
      <div className="space-y-2">
        {Array.from({ length: 8 }).map((_, i) => (
          <Skeleton key={i} className="h-12 w-full" />
        ))}
      </div>
    </div>
  );
}

/** Skeleton block used for content placeholders (shimmer in light + dark). */
export function Skeleton({ className = "" }: { className?: string }) {
  return (
    <div className={`relative overflow-hidden rounded-md bg-muted ${className}`}>
      <div className="absolute inset-0 -translate-x-full animate-[shimmer_1.5s_infinite] bg-gradient-to-r from-transparent via-foreground/5 to-transparent" />
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
    <div className="flex animate-fade-in flex-col items-center justify-center gap-3 rounded-xl border border-dashed p-12 text-center">
      <div className="flex h-12 w-12 items-center justify-center rounded-full bg-muted text-muted-foreground">
        <Inbox className="h-6 w-6" />
      </div>
      <p className="font-medium">{title}</p>
      {hint && <p className="max-w-sm text-sm text-muted-foreground">{hint}</p>}
      {action && <div className="mt-1">{action}</div>}
    </div>
  );
}

export function ErrorState({ message }: { message: string }) {
  return (
    <div className="m-2 flex animate-fade-in items-start gap-3 rounded-lg border border-destructive/30 bg-destructive/10 p-4 text-destructive">
      <AlertCircle className="mt-0.5 h-5 w-5 shrink-0" />
      <div>
        <p className="font-medium">Something went wrong</p>
        <p className="text-sm opacity-90">{message}</p>
      </div>
    </div>
  );
}

export function NoPermissionState({ perm }: { perm?: string }) {
  return (
    <div className="m-2 flex animate-fade-in items-start gap-3 rounded-lg border border-warning/30 bg-warning/10 p-4">
      <Lock className="mt-0.5 h-5 w-5 shrink-0 text-warning" />
      <div>
        <p className="font-medium">You don't have access to this</p>
        <p className="text-sm text-muted-foreground">
          Ask a workspace admin for the
          {perm ? (
            <code className="mx-1 rounded bg-muted px-1 py-0.5 text-xs">{perm}</code>
          ) : (
            " required "
          )}
          permission.
        </p>
      </div>
    </div>
  );
}
