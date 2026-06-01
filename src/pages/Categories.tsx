// Categories (§6.7). CRUD; income/expense; system categories read-only.
// Sortable headers; rows open a detail modal; actions in a kebab menu.

import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Plus, Pencil, Trash2, Lock, ArrowLeftRight } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { createCategory, deleteCategory, updateCategory } from "@/data/mutations";
import { txnsByCategory } from "@/lib/links";
import { roundMoney } from "@/lib/txn";
import { toDate } from "@/lib/derive";
import { financialYearOf } from "@/lib/financialYear";
import { formatMoney } from "@/lib/utils";
import type { Category, CategoryKind } from "@/types/models";
import { PageHeader } from "@/components/PageHeader";
import { RowActions, type RowAction } from "@/components/RowActions";
import { SortableHead } from "@/components/SortableHead";
import { ResizableTable } from "@/components/ResizableTable";
import { useColumnWidths } from "@/lib/useColumnWidths";
import { DetailDialog } from "@/components/DetailDialog";
import { useSort, type SortAccessor } from "@/lib/useSort";
import { usePagination } from "@/lib/usePagination";
import { Pagination } from "@/components/Pagination";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
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
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { EmptyState, ErrorState, PageSkeleton } from "@/components/states";
import { useToast } from "@/components/ui/toast";

type SortKey = "name" | "amount" | "source";

export function Categories() {
  const navigate = useNavigate();
  const colWidths = useColumnWidths("categories");
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { categories, transactions, loading, error } = useData();
  const { toast } = useToast();
  const manage = can("categories.manage");
  const canViewTxns = can("transactions.view");
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const fyStartMonth = activeWorkspace?.fyStartMonth ?? 4;
  const fy = financialYearOf(new Date(), fyStartMonth);

  // Net amount per category for the CURRENT financial year — the sum of line
  // amounts tagged with it (total spent for expense categories, total earned
  // for income). FY-scoped to match the Reports/Dashboard breakdowns. Derived.
  const amountByCategory = useMemo(() => {
    const totals: Record<string, number> = {};
    for (const t of transactions) {
      if (financialYearOf(toDate(t.date), fyStartMonth) !== fy) continue;
      for (const l of t.lines) {
        if (l.categoryId) {
          totals[l.categoryId] = roundMoney((totals[l.categoryId] ?? 0) + l.amount);
        }
      }
    }
    return totals;
  }, [transactions, fy, fyStartMonth]);

  const [kind, setKind] = useState<CategoryKind>("expense");
  const [editing, setEditing] = useState<Category | "new" | null>(null);
  const [viewing, setViewing] = useState<Category | null>(null);
  const [toDelete, setToDelete] = useState<Category | null>(null);

  if (loading) return <PageSkeleton />;
  if (error) return <ErrorState message={error} />;

  const filtered = categories.filter((c) => c.kind === kind);
  const accessors: Record<SortKey, SortAccessor<Category>> = {
    name: (c) => c.name,
    amount: (c) => amountByCategory[c.id] ?? 0,
    source: (c) => (c.isSystem ? "System" : "Custom"),
  };
  const { sorted, sort, toggle } = useSort(filtered, accessors, {
    key: "name",
    direction: "asc",
  });
  const pagination = usePagination(sorted);
  const { pageItems } = pagination;

  function rowActions(c: Category): RowAction[] {
    return [
      {
        label: "View transactions",
        icon: ArrowLeftRight,
        onSelect: () => navigate(txnsByCategory(c.id)),
        hidden: !canViewTxns,
      },
      {
        label: "Edit",
        icon: Pencil,
        onSelect: () => setEditing(c),
        separatorBefore: true,
        hidden: !manage,
        disabled: c.isSystem,
      },
      {
        label: "Delete",
        icon: Trash2,
        onSelect: () => setToDelete(c),
        destructive: true,
        separatorBefore: true,
        hidden: !manage,
        disabled: c.isSystem,
      },
    ];
  }

  return (
    <div>
      <PageHeader
        title="Categories"
        primaryAction={{
          label: "New category",
          icon: Plus,
          onClick: () => setEditing("new"),
          hidden: !manage,
        }}
      />

      <Tabs
        value={kind}
        onValueChange={(v) => { setKind(v as CategoryKind); pagination.reset(); }}
        className="mb-4"
      >
        <TabsList>
          <TabsTrigger value="expense">Expense</TabsTrigger>
          <TabsTrigger value="income">Income</TabsTrigger>
        </TabsList>
      </Tabs>

      {sorted.length === 0 ? (
        <EmptyState title={`No ${kind} categories`} />
      ) : (
        <ResizableTable prefs={colWidths} className="[&_td]:truncate">
          <TableHeader>
            <TableRow>
              <SortableHead sortKey="name" sort={sort} onToggle={toggle}>
                Name
              </SortableHead>
              <SortableHead sortKey="amount" sort={sort} onToggle={toggle} align="right">
                Net · FY {fy}
              </SortableHead>
              <SortableHead sortKey="source" sort={sort} onToggle={toggle}>
                Source
              </SortableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {pageItems.map((c) => (
              <TableRow
                key={c.id}
                onClick={() => setViewing(c)}
                className="cursor-pointer"
              >
                <TableCell className="font-medium">{c.name}</TableCell>
                <TableCell className="text-right tabular-nums">
                  {formatMoney(amountByCategory[c.id] ?? 0, currency)}
                </TableCell>
                <TableCell>
                  {c.isSystem ? (
                    <Badge variant="outline">
                      <Lock className="mr-1 h-3 w-3" /> System
                    </Badge>
                  ) : (
                    <Badge variant="secondary">Custom</Badge>
                  )}
                </TableCell>
                <TableCell>
                  <RowActions actions={rowActions(c)} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </ResizableTable>
      )}

      {sorted.length > 0 && <Pagination state={pagination} noun="categories" />}

      {viewing && (
        <DetailDialog
          open
          onClose={() => setViewing(null)}
          title={viewing.name}
          fields={[
            { label: "Kind", value: viewing.kind === "income" ? "Income" : "Expense" },
            { label: "Source", value: viewing.isSystem ? "System (read-only)" : "Custom" },
          ]}
          actions={rowActions(viewing)}
          entityId={viewing.id}
          audit={{
            createdBy: viewing.createdBy,
            createdAt: viewing.createdAt,
            updatedBy: viewing.updatedBy,
            updatedAt: viewing.updatedAt,
          }}
        />
      )}

      {editing && activeWorkspaceId && (
        <CategoryDialog
          workspaceId={activeWorkspaceId}
          defaultKind={kind}
          category={editing === "new" ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={() => toast({ title: "Category saved", variant: "success" })}
        />
      )}

      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title={`Delete "${toDelete?.name}"?`}
        destructive
        confirmLabel="Delete"
        onConfirm={async () => {
          if (toDelete) {
            await deleteCategory(toDelete.id);
            toast({ title: "Category deleted", variant: "success" });
          }
        }}
      />
    </div>
  );
}

function CategoryDialog({
  workspaceId,
  category,
  defaultKind,
  onClose,
  onSaved,
}: {
  workspaceId: string;
  category: Category | null;
  defaultKind: CategoryKind;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(category?.name ?? "");
  const [kind, setKind] = useState<CategoryKind>(category?.kind ?? defaultKind);
  const [busy, setBusy] = useState(false);

  async function save() {
    if (!name.trim()) return;
    setBusy(true);
    try {
      if (category) await updateCategory(category.id, { name: name.trim(), kind });
      else await createCategory(workspaceId, { name: name.trim(), kind });
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
          <DialogTitle>{category ? "Edit category" : "New category"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="cat-name">Name</Label>
            <Input id="cat-name" value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label>Kind</Label>
            <Select value={kind} onValueChange={(v) => setKind(v as CategoryKind)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="expense">Expense</SelectItem>
                <SelectItem value="income">Income</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !name.trim()}>
            {busy ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
