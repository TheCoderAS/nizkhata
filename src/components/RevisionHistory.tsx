// Revision history for an entity, shown inside detail modals. Renders a compact
// timeline of who did what, when. Also exposes a one-line "audit footer" for
// entities whose docs carry createdBy/updatedBy.

import { Plus, Pencil, Trash2, History } from "lucide-react";
import { useRevisions } from "@/data/useRevisions";
import { toDate } from "@/lib/derive";
import { formatRelative } from "@/lib/utils";
import type { Actor, RevisionAction, Ts } from "@/types/models";

const ACTION_ICON: Record<RevisionAction, typeof Plus> = {
  create: Plus,
  update: Pencil,
  delete: Trash2,
};
const ACTION_LABEL: Record<RevisionAction, string> = {
  create: "created",
  update: "edited",
  delete: "deleted",
};

export function RevisionHistory({ entityId }: { entityId: string }) {
  const { revisions, loading, error } = useRevisions(entityId);

  if (loading) {
    return <p className="py-2 text-xs text-muted-foreground">Loading history…</p>;
  }
  if (error) {
    return <p className="py-2 text-xs text-destructive">Couldn't load history.</p>;
  }
  if (revisions.length === 0) {
    return <p className="py-2 text-xs text-muted-foreground">No history recorded.</p>;
  }

  return (
    <ol className="space-y-2.5">
      {revisions.map((r) => {
        const Icon = ACTION_ICON[r.action];
        const changed =
          r.action === "update" && r.changedFields?.length
            ? ` · ${r.changedFields.join(", ")}`
            : "";
        return (
          <li key={r.id} className="flex items-start gap-2 text-sm">
            <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-muted text-muted-foreground">
              <Icon className="h-3 w-3" />
            </span>
            <div className="min-w-0">
              <span className="font-medium">{r.by?.name ?? "Someone"}</span>{" "}
              <span className="text-muted-foreground">
                {ACTION_LABEL[r.action]}
                {changed}
              </span>
              <div className="text-xs text-muted-foreground">
                {r.at ? formatRelative(toDate(r.at)) : ""}
              </div>
            </div>
          </li>
        );
      })}
    </ol>
  );
}

/** Compact one-liner for a modal footer using the doc's own audit fields. */
export function AuditFooter({
  createdBy,
  createdAt,
  updatedBy,
  updatedAt,
}: {
  createdBy?: Actor;
  createdAt?: Ts;
  updatedBy?: Actor;
  updatedAt?: Ts;
}) {
  if (!createdBy && !updatedBy) return null;
  const edited =
    updatedBy && updatedAt && createdAt && toDate(updatedAt) > toDate(createdAt);
  return (
    <p className="flex items-center gap-1.5 pt-1 text-xs text-muted-foreground">
      <History className="h-3 w-3" />
      {createdBy && (
        <span>
          Added by {createdBy.name}
          {createdAt ? ` · ${formatRelative(toDate(createdAt))}` : ""}
        </span>
      )}
      {edited && (
        <span>
          · edited by {updatedBy!.name} · {formatRelative(toDate(updatedAt!))}
        </span>
      )}
    </p>
  );
}
