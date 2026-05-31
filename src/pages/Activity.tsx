// Workspace activity feed — a chronological, human-readable view of the
// append-only revision log: who created/updated/deleted what, when. Grouped by
// day. Entity names are resolved client-side from live data, falling back to
// the revision snapshot for entities that have since been deleted.

import { useMemo } from "react";
import {
  ArrowLeftRight,
  CalendarClock,
  HandCoins,
  Pencil,
  Plus,
  Tags,
  Target,
  Trash2,
  Users,
  Wallet,
  type LucideIcon,
} from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { useWorkspaceActivity } from "@/data/useWorkspaceActivity";
import { toDate } from "@/lib/derive";
import { formatRelative } from "@/lib/utils";
import { PageHeader } from "@/components/PageHeader";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState, ErrorState, LoadingState } from "@/components/states";
import type { Revision, RevisionAction } from "@/types/models";

const ENTITY_META: Record<string, { label: string; icon: LucideIcon }> = {
  transactions: { label: "transaction", icon: ArrowLeftRight },
  accounts: { label: "account", icon: Wallet },
  categories: { label: "category", icon: Tags },
  contacts: { label: "contact", icon: Users },
  debts: { label: "debt", icon: HandCoins },
  dues: { label: "due", icon: CalendarClock },
  budgets: { label: "budget", icon: Target },
};

const ACTION_VERB: Record<RevisionAction, string> = {
  create: "added",
  update: "updated",
  delete: "deleted",
};

const ACTION_ICON: Record<RevisionAction, LucideIcon> = {
  create: Plus,
  update: Pencil,
  delete: Trash2,
};

const DAY_FMT = new Intl.DateTimeFormat("en-IN", {
  weekday: "long",
  day: "numeric",
  month: "long",
  year: "numeric",
});

export function Activity() {
  const { activeWorkspaceId } = useWorkspace();
  const data = useData();
  const { activity, loading, error } = useWorkspaceActivity(activeWorkspaceId);

  // Resolve a revision's entity to a display name from live data, falling back
  // to the snapshot (for deleted entities) and finally a short id.
  const describe = useMemo(() => {
    const nameFromSnapshot = (snap?: Record<string, unknown>): string | null => {
      if (!snap) return null;
      for (const key of ["name", "title", "description", "note"]) {
        const v = snap[key];
        if (typeof v === "string" && v.trim()) return v;
      }
      return null;
    };
    return (r: Revision): string => {
      switch (r.entityType) {
        case "accounts":
          return data.accountsById[r.entityId]?.name ?? nameFromSnapshot(r.snapshot) ?? "account";
        case "categories":
          return (
            data.categoriesById[r.entityId]?.name ?? nameFromSnapshot(r.snapshot) ?? "category"
          );
        case "contacts":
          return data.contactsById[r.entityId]?.name ?? nameFromSnapshot(r.snapshot) ?? "contact";
        case "budgets": {
          const b = data.budgets.find((x) => x.id === r.entityId);
          const catId = b?.categoryId ?? (r.snapshot?.categoryId as string | undefined);
          return catId ? (data.categoriesById[catId]?.name ?? "category") : "budget";
        }
        case "dues": {
          const d = data.dues.find((x) => x.id === r.entityId);
          return d?.title ?? nameFromSnapshot(r.snapshot) ?? "due";
        }
        case "transactions": {
          const t = data.transactions.find((x) => x.id === r.entityId);
          const note = t?.note ?? nameFromSnapshot(r.snapshot);
          return note ?? "transaction";
        }
        default:
          return nameFromSnapshot(r.snapshot) ?? "item";
      }
    };
  }, [data]);

  const groups = useMemo(() => {
    const byDay = new Map<string, Revision[]>();
    for (const r of activity) {
      const d = r.at ? toDate(r.at) : new Date();
      const key = `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
      const list = byDay.get(key) ?? [];
      list.push(r);
      byDay.set(key, list);
    }
    return [...byDay.entries()].map(([key, items]) => {
      const sample = items[0].at ? toDate(items[0].at) : new Date();
      return { key, label: DAY_FMT.format(sample), items };
    });
  }, [activity]);

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  return (
    <div>
      <PageHeader title="Activity" />

      <div className="mt-4" />

      {activity.length === 0 ? (
        <EmptyState
          title="No activity yet"
          hint="Changes to transactions, accounts, budgets and more will show up here."
        />
      ) : (
        <div className="space-y-6">
          {groups.map((g) => (
            <section key={g.key}>
              <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                {g.label}
              </h2>
              <Card>
                <CardContent className="divide-y p-0">
                  {g.items.map((r) => {
                    const meta = ENTITY_META[r.entityType] ?? {
                      label: r.entityType,
                      icon: Pencil,
                    };
                    const ActionIcon = ACTION_ICON[r.action];
                    const when = r.at ? formatRelative(toDate(r.at)) : "just now";
                    return (
                      <div key={r.id} className="flex items-start gap-3 px-4 py-3 text-sm">
                        <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-muted text-muted-foreground">
                          <ActionIcon className="h-3.5 w-3.5" />
                        </span>
                        <div className="min-w-0 flex-1">
                          <p className="leading-snug">
                            <span className="font-medium">{r.by?.name ?? "Someone"}</span>{" "}
                            {ACTION_VERB[r.action]} {meta.label}{" "}
                            <span className="font-medium">{describe(r)}</span>
                            {r.action === "update" &&
                              r.changedFields &&
                              r.changedFields.length > 0 && (
                                <span className="text-muted-foreground">
                                  {" "}
                                  ({r.changedFields.join(", ")})
                                </span>
                              )}
                          </p>
                          <p className="text-xs text-muted-foreground">{when}</p>
                        </div>
                        <meta.icon className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
                      </div>
                    );
                  })}
                </CardContent>
              </Card>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
