// Settings › Budgets. Monthly spending limits per expense category, with live
// progress derived from this month's transactions. Gated by categories.manage.

import { useMemo, useState } from "react";
import { Plus, Pencil, Trash2 } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { createBudget, deleteBudget, updateBudget } from "@/data/mutations";
import { budgetProgress } from "@/lib/derive";
import type { Budget } from "@/types/models";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { EmptyState, ErrorState, LoadingState } from "@/components/states";
import { useToast } from "@/components/ui/toast";
import { cn, formatMoney } from "@/lib/utils";

const MONTH_LABEL = new Intl.DateTimeFormat("en-IN", { month: "long", year: "numeric" });

export function Budgets() {
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { budgets, categories, categoriesById, transactions, loading, error } = useData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const manage = can("categories.manage");

  const [editing, setEditing] = useState<Budget | "new" | null>(null);
  const [toDelete, setToDelete] = useState<Budget | null>(null);

  const progress = useMemo(
    () => budgetProgress(budgets, transactions, categoriesById),
    [budgets, transactions, categoriesById],
  );

  const totals = useMemo(() => {
    const limit = progress.reduce((s, p) => s + p.limit, 0);
    const spent = progress.reduce((s, p) => s + p.spent, 0);
    return { limit, spent, remaining: limit - spent };
  }, [progress]);

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  return (
    <div>
      <PageHeader
        title="Budgets"
        primaryAction={{
          label: "New budget",
          icon: Plus,
          onClick: () => setEditing("new"),
          hidden: !manage,
        }}
      />

      <p className="mb-4 text-sm text-muted-foreground">{MONTH_LABEL.format(new Date())}</p>

      {budgets.length === 0 ? (
        <EmptyState
          title="No budgets yet"
          hint="Set a monthly limit on an expense category to track spending against it."
          action={manage && <Button onClick={() => setEditing("new")}>New budget</Button>}
        />
      ) : (
        <>
          <Card className="mb-4">
            <CardContent className="flex flex-wrap items-center justify-between gap-4 pt-6">
              <Stat label="Total budget" value={formatMoney(totals.limit, currency)} />
              <Stat label="Spent" value={formatMoney(totals.spent, currency)} />
              <Stat
                label="Remaining"
                value={formatMoney(totals.remaining, currency)}
                tone={totals.remaining < 0 ? "over" : "ok"}
              />
            </CardContent>
          </Card>

          <div className="space-y-3">
            {progress.map((p) => {
              const budget = budgets.find((b) => b.id === p.budgetId)!;
              const pct = Math.min(100, Math.round(p.ratio * 100));
              return (
                <Card key={p.budgetId}>
                  <CardContent className="pt-5">
                    <div className="mb-2 flex items-center justify-between gap-2">
                      <span className="font-medium">{p.categoryName}</span>
                      <div className="flex items-center gap-2">
                        <span
                          className={cn(
                            "text-sm tabular-nums",
                            p.over ? "text-destructive" : "text-muted-foreground",
                          )}
                        >
                          {formatMoney(p.spent, currency)} / {formatMoney(p.limit, currency)}
                        </span>
                        {manage && (
                          <>
                            <Button size="icon" variant="ghost" onClick={() => setEditing(budget)}>
                              <Pencil />
                            </Button>
                            <Button size="icon" variant="ghost" onClick={() => setToDelete(budget)}>
                              <Trash2 />
                            </Button>
                          </>
                        )}
                      </div>
                    </div>
                    <div className="h-2 w-full overflow-hidden rounded-full bg-muted">
                      <div
                        className={cn(
                          "h-2 rounded-full transition-all",
                          p.over ? "bg-destructive" : p.ratio > 0.8 ? "bg-warning" : "bg-primary",
                        )}
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                    <p
                      className={cn(
                        "mt-1 text-xs",
                        p.over ? "text-destructive" : "text-muted-foreground",
                      )}
                    >
                      {p.over
                        ? `Over by ${formatMoney(-p.remaining, currency)}`
                        : `${formatMoney(p.remaining, currency)} left`}
                    </p>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        </>
      )}

      {editing && activeWorkspaceId && (
        <BudgetDialog
          budget={editing === "new" ? null : editing}
          existingCategoryIds={budgets.map((b) => b.categoryId)}
          expenseCategories={categories.filter((c) => c.kind === "expense")}
          onClose={() => setEditing(null)}
          onSaved={() => toast({ title: "Budget saved", variant: "success" })}
        />
      )}

      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title="Delete budget?"
        destructive
        confirmLabel="Delete"
        onConfirm={async () => {
          if (toDelete) {
            await deleteBudget(toDelete.id);
            toast({ title: "Budget deleted", variant: "success" });
          }
        }}
      />
    </div>
  );
}

function Stat({
  label,
  value,
  tone,
}: {
  label: string;
  value: string;
  tone?: "ok" | "over";
}) {
  return (
    <div>
      <p className="text-xs text-muted-foreground">{label}</p>
      <p
        className={cn(
          "text-lg font-semibold tabular-nums",
          tone === "over" && "text-destructive",
        )}
      >
        {value}
      </p>
    </div>
  );
}

function BudgetDialog({
  budget,
  expenseCategories,
  existingCategoryIds,
  onClose,
  onSaved,
}: {
  budget: Budget | null;
  expenseCategories: { id: string; name: string }[];
  existingCategoryIds: string[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const { activeWorkspaceId } = useWorkspace();
  const [categoryId, setCategoryId] = useState(budget?.categoryId ?? "");
  const [amount, setAmount] = useState(String(budget?.amount ?? 0));
  const [busy, setBusy] = useState(false);

  // when creating, only offer categories that don't already have a budget
  const options = budget
    ? expenseCategories
    : expenseCategories.filter((c) => !existingCategoryIds.includes(c.id));

  async function save() {
    if (!categoryId || !activeWorkspaceId) return;
    setBusy(true);
    try {
      if (budget) await updateBudget(budget.id, { amount: Number(amount) || 0 });
      else await createBudget(activeWorkspaceId, { categoryId, amount: Number(amount) || 0 });
      onSaved();
      onClose();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{budget ? "Edit budget" : "New budget"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label>Category</Label>
            <Select value={categoryId} onValueChange={setCategoryId} disabled={!!budget}>
              <SelectTrigger>
                <SelectValue placeholder="Select expense category" />
              </SelectTrigger>
              <SelectContent>
                {options.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Monthly limit</Label>
            <Input
              type="number"
              min="0"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !categoryId}>
            {busy ? "Saving…" : "Save budget"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
