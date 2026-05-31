// Settings › Budgets. Monthly spending limits per expense category, with live
// progress derived from this month's transactions. Gated by categories.manage.

import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Plus, Pencil, Trash2 } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { createBudget, deleteBudget, updateBudget } from "@/data/mutations";
import { budgetProgress } from "@/lib/derive";
import type { Budget, BudgetPeriod } from "@/types/models";
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
import { RowActions } from "@/components/RowActions";
import { EmptyState, ErrorState, PageSkeleton } from "@/components/states";
import { useToast } from "@/components/ui/toast";
import { cn, formatMoney } from "@/lib/utils";

export function Budgets() {
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { budgets, categories, categoriesById, transactions, loading, error } = useData();
  const { toast } = useToast();
  const navigate = useNavigate();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const fyStartMonth = activeWorkspace?.fyStartMonth ?? 4;
  const manage = can("categories.manage");
  const canViewTxns = can("transactions.view");

  // Open the Transactions screen pre-filtered to this budget's category.
  const openTxns = (categoryId: string) =>
    navigate(`/transactions?category=${encodeURIComponent(categoryId)}`);

  const [editing, setEditing] = useState<Budget | "new" | null>(null);
  const [toDelete, setToDelete] = useState<Budget | null>(null);

  const progress = useMemo(
    () => budgetProgress(budgets, transactions, categoriesById, fyStartMonth),
    [budgets, transactions, categoriesById, fyStartMonth],
  );

  // Group by period — monthly and yearly limits aren't comparable, so totals
  // and lists are kept separate.
  const groups = useMemo(() => {
    const order: BudgetPeriod[] = ["monthly", "yearly"];
    return order
      .map((period) => {
        const rows = progress.filter((p) => p.period === period);
        const limit = rows.reduce((s, p) => s + p.limit, 0);
        const spent = rows.reduce((s, p) => s + p.spent, 0);
        return { period, rows, limit, spent, remaining: limit - spent };
      })
      .filter((g) => g.rows.length > 0);
  }, [progress]);

  if (loading) return <PageSkeleton />;
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

      <div className="mt-4" />

      {budgets.length === 0 ? (
        <EmptyState
          title="No budgets yet"
          hint="Set a monthly or yearly limit on an expense category to track spending against it."
          action={manage && <Button onClick={() => setEditing("new")}>New budget</Button>}
        />
      ) : (
        <div className="space-y-6">
          {groups.map((g) => (
            <section key={g.period}>
              <div className="mb-2 flex items-end justify-between gap-2">
                <h2 className="text-sm font-semibold capitalize">{g.period} budgets</h2>
                <span className="text-xs text-muted-foreground tabular-nums">
                  {formatMoney(g.spent, currency)} / {formatMoney(g.limit, currency)}
                  <span className={cn("ml-2", g.remaining < 0 && "text-destructive")}>
                    ({g.remaining < 0 ? "over by " : ""}
                    {formatMoney(Math.abs(g.remaining), currency)}
                    {g.remaining < 0 ? "" : " left"})
                  </span>
                </span>
              </div>
              <div className="space-y-3">
                {g.rows.map((p) => {
                  const budget = budgets.find((b) => b.id === p.budgetId)!;
                  const pct = Math.min(100, Math.round(p.ratio * 100));
                  return (
                    <Card
                      key={p.budgetId}
                      role={canViewTxns ? "button" : undefined}
                      tabIndex={canViewTxns ? 0 : undefined}
                      onClick={canViewTxns ? () => openTxns(p.categoryId) : undefined}
                      onKeyDown={
                        canViewTxns
                          ? (e) => {
                              if (e.key === "Enter" || e.key === " ") {
                                e.preventDefault();
                                openTxns(p.categoryId);
                              }
                            }
                          : undefined
                      }
                      className={cn(
                        canViewTxns &&
                          "cursor-pointer transition-colors hover:border-primary/50 hover:bg-accent/40",
                      )}
                    >
                      <CardContent className="pt-5">
                        <div className="mb-2 flex items-start justify-between gap-2">
                          <div className="min-w-0">
                            <div className="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
                              <span className="font-medium">{p.categoryName}</span>
                              <span className="text-xs text-muted-foreground">
                                {p.periodLabel}
                              </span>
                            </div>
                            <div
                              className={cn(
                                "mt-0.5 text-sm tabular-nums",
                                p.over ? "text-destructive" : "text-muted-foreground",
                              )}
                            >
                              {formatMoney(p.spent, currency)} / {formatMoney(p.limit, currency)}
                            </div>
                          </div>
                          {manage && (
                            <div className="-mr-2 -mt-1 shrink-0">
                            <RowActions
                              actions={[
                                {
                                  label: "Edit",
                                  icon: Pencil,
                                  onSelect: () => setEditing(budget),
                                },
                                {
                                  label: "Delete",
                                  icon: Trash2,
                                  onSelect: () => setToDelete(budget),
                                  destructive: true,
                                },
                              ]}
                            />
                            </div>
                          )}
                        </div>
                        <div className="h-2 w-full overflow-hidden rounded-full bg-muted">
                          <div
                            className={cn(
                              "h-2 rounded-full transition-all",
                              p.over
                                ? "bg-destructive"
                                : p.ratio > 0.8
                                  ? "bg-warning"
                                  : "bg-primary",
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
            </section>
          ))}
        </div>
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
  const [period, setPeriod] = useState<BudgetPeriod>(budget?.period ?? "monthly");
  const [busy, setBusy] = useState(false);

  // when creating, only offer categories that don't already have a budget
  const options = budget
    ? expenseCategories
    : expenseCategories.filter((c) => !existingCategoryIds.includes(c.id));

  async function save() {
    if (!categoryId || !activeWorkspaceId) return;
    setBusy(true);
    try {
      if (budget) await updateBudget(budget.id, { amount: Number(amount) || 0, period });
      else
        await createBudget(activeWorkspaceId, { categoryId, amount: Number(amount) || 0, period });
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
            <Label>Period</Label>
            <Select value={period} onValueChange={(v) => setPeriod(v as BudgetPeriod)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="monthly">Monthly</SelectItem>
                <SelectItem value="yearly">Yearly (financial year)</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>{period === "yearly" ? "Yearly limit" : "Monthly limit"}</Label>
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
