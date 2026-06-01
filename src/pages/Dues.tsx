// Dues (§6.4). Payable/receivable obligations with status + due date.
// Create / edit / delete; "Record payment" creates a transaction linked via
// dueId; partial settlement keeps the due in "partial" until fully covered.
// Sortable headers, clickable rows -> detail modal, kebab row actions.

import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Plus, Receipt, Pencil, Trash2, Ban, Users, ArrowLeftRight } from "lucide-react";
import { Timestamp } from "firebase/firestore";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import {
  createDue,
  deleteDue,
  settleDue,
  updateDue,
  type TransactionInput,
} from "@/data/mutations";
import { txnsByContact, contactDetailPath } from "@/lib/links";
import type { Due, DueDirection } from "@/types/models";
import { dueStatusFromSettled, toDate } from "@/lib/derive";
import { PageHeader } from "@/components/PageHeader";
import { TransactionFormDialog } from "@/components/TransactionForm";
import { RowActions, type RowAction } from "@/components/RowActions";
import { SortableHead } from "@/components/SortableHead";
import { DetailDialog, type DetailField } from "@/components/DetailDialog";
import { FilterModal, FilterRow } from "@/components/FilterModal";
import { ColumnsMenu } from "@/components/ColumnsMenu";
import { ResizableTable } from "@/components/ResizableTable";
import { Toolbar } from "@/components/Toolbar";
import { useColumnPrefs, type ColumnDef } from "@/lib/useColumnPrefs";
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
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { EmptyState, ErrorState, PageSkeleton } from "@/components/states";
import { useToast } from "@/components/ui/toast";
import { formatDate, formatMoney } from "@/lib/utils";

type SortKey = "title" | "direction" | "contact" | "dueDate" | "amount" | "settled" | "status";
type ColKey = "title" | "direction" | "contact" | "dueDate" | "amount" | "settled" | "status";

const COLUMNS: ColumnDef<ColKey>[] = [
  { key: "title", label: "Title", defaultVisible: true, locked: true },
  { key: "direction", label: "Direction", defaultVisible: false },
  { key: "contact", label: "Contact", defaultVisible: false },
  { key: "dueDate", label: "Due date", defaultVisible: true },
  { key: "amount", label: "Amount", defaultVisible: true },
  { key: "settled", label: "Settled", defaultVisible: false },
  { key: "status", label: "Status", defaultVisible: true },
];

export function Dues() {
  const navigate = useNavigate();
  const { firebaseUser } = useAuth();
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { dues, contactsById, accountsById, settledOf, loading, error } = useData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const manage = can("dues.manage");
  const canTxn = can("transactions.create");
  const canViewTxns = can("transactions.view");
  const canViewContacts = can("contacts.view");

  const [editing, setEditing] = useState<Due | "new" | null>(null);
  const [viewing, setViewing] = useState<Due | null>(null);
  const [paying, setPaying] = useState<Due | null>(null);
  const [toDelete, setToDelete] = useState<Due | null>(null);

  const [search, setSearch] = useState("");
  const [directionFilter, setDirectionFilter] = useState("__all");
  const [statusFilter, setStatusFilter] = useState("__all");

  const cols = useColumnPrefs<ColKey>("dues", COLUMNS);

  const filteredDues = dues.filter((d) => {
    if (directionFilter !== "__all" && d.direction !== directionFilter) return false;
    if (statusFilter !== "__all" && dueStatusFromSettled(d, settledOf(d.id)) !== statusFilter)
      return false;
    if (search) {
      const hay = `${d.title} ${
        d.contactId ? contactsById[d.contactId]?.name ?? "" : ""
      }`.toLowerCase();
      if (!hay.includes(search.toLowerCase())) return false;
    }
    return true;
  });
  const activeFilterCount =
    (directionFilter !== "__all" ? 1 : 0) + (statusFilter !== "__all" ? 1 : 0);
  function clearFilters() {
    setDirectionFilter("__all");
    setStatusFilter("__all");
  }

  const accessors: Record<SortKey, SortAccessor<Due>> = {
    title: (d) => d.title,
    direction: (d) => d.direction,
    contact: (d) => (d.contactId ? contactsById[d.contactId]?.name ?? "" : ""),
    dueDate: (d) => toDate(d.dueDate),
    amount: (d) => d.amount,
    settled: (d) => settledOf(d.id),
    status: (d) => dueStatusFromSettled(d, settledOf(d.id)),
  };
  const { sorted, sort, toggle } = useSort(filteredDues, accessors, {
    key: "dueDate",
    direction: "asc",
  });
  const pagination = usePagination(sorted);
  const { pageItems } = pagination;

  if (loading) return <PageSkeleton />;
  if (error) return <ErrorState message={error} />;

  function rowActions(d: Due): RowAction[] {
    const status = dueStatusFromSettled(d, settledOf(d.id));
    const settleable = status !== "settled" && status !== "cancelled";
    return [
      {
        label: "Record payment",
        icon: Receipt,
        onSelect: () => setPaying(d),
        hidden: !canTxn || !settleable,
      },
      {
        label: "View contact",
        icon: Users,
        onSelect: () => d.contactId && navigate(contactDetailPath(d.contactId)),
        separatorBefore: true,
        hidden: !canViewContacts || !d.contactId,
      },
      {
        label: "View transactions",
        icon: ArrowLeftRight,
        onSelect: () => d.contactId && navigate(txnsByContact(d.contactId)),
        hidden: !canViewTxns || !d.contactId,
      },
      { label: "Edit", icon: Pencil, onSelect: () => setEditing(d), separatorBefore: true, hidden: !manage },
      {
        label: "Cancel due",
        icon: Ban,
        onSelect: () => void cancelDue(d),
        hidden: !manage || status === "cancelled" || status === "settled",
      },
      {
        label: "Delete",
        icon: Trash2,
        onSelect: () => setToDelete(d),
        destructive: true,
        separatorBefore: true,
        hidden: !manage,
      },
    ];
  }

  async function cancelDue(d: Due) {
    await updateDue(d.id, { status: "cancelled" });
    toast({ title: "Due cancelled", variant: "success" });
  }

  async function handlePay(input: TransactionInput) {
    if (!activeWorkspaceId || !firebaseUser || !paying) return;
    const alreadySettled = settledOf(paying.id);
    const newSettled = alreadySettled + Math.abs(input.totalAmount);
    const status = dueStatusFromSettled(paying, newSettled);
    await settleDue(activeWorkspaceId, firebaseUser.uid, paying, input, status);
    toast({
      title: status === "settled" ? "Due settled" : "Partial payment recorded",
      variant: "success",
    });
  }

  return (
    <div>
      <PageHeader
        title="Dues"
        primaryAction={{
          label: "New due",
          icon: Plus,
          onClick: () => setEditing("new"),
          hidden: !manage,
        }}
      />

      {dues.length > 0 && (
        <Toolbar
          search={search}
          onSearch={(v) => { setSearch(v); pagination.reset(); }}
          placeholder="Search dues…"
        >
          <FilterModal activeCount={activeFilterCount} onClear={clearFilters}>
            <FilterRow label="Direction">
              <DueFilterSelect
                value={directionFilter}
                onChange={setDirectionFilter}
                allLabel="All directions"
                options={[
                  { value: "payable", label: "Payable" },
                  { value: "receivable", label: "Receivable" },
                ]}
              />
            </FilterRow>
            <FilterRow label="Status">
              <DueFilterSelect
                value={statusFilter}
                onChange={setStatusFilter}
                allLabel="All statuses"
                options={[
                  { value: "open", label: "Open" },
                  { value: "partial", label: "Partial" },
                  { value: "settled", label: "Settled" },
                  { value: "cancelled", label: "Cancelled" },
                ]}
              />
            </FilterRow>
          </FilterModal>
          <ColumnsMenu columns={cols.columns} isVisible={cols.isVisible} toggle={cols.toggle} reset={cols.reset} hasCustomWidths={cols.hasCustomWidths} onResetWidths={cols.resetWidths} />
        </Toolbar>
      )}

      {dues.length === 0 ? (
        <EmptyState
          title="No dues"
          hint="Track upcoming bills (payable) or expected income (receivable)."
          action={manage && <Button onClick={() => setEditing("new")}>New due</Button>}
        />
      ) : (
        <ResizableTable prefs={cols} className="[&_td]:truncate">
          <TableHeader>
            <TableRow>
              {cols.isVisible("title") && (
                <SortableHead sortKey="title" sort={sort} onToggle={toggle}>
                  Title
                </SortableHead>
              )}
              {cols.isVisible("direction") && (
                <SortableHead sortKey="direction" sort={sort} onToggle={toggle}>
                  Direction
                </SortableHead>
              )}
              {cols.isVisible("contact") && (
                <SortableHead sortKey="contact" sort={sort} onToggle={toggle}>
                  Contact
                </SortableHead>
              )}
              {cols.isVisible("dueDate") && (
                <SortableHead sortKey="dueDate" sort={sort} onToggle={toggle}>
                  Due date
                </SortableHead>
              )}
              {cols.isVisible("amount") && (
                <SortableHead sortKey="amount" sort={sort} onToggle={toggle} className="text-right">
                  Amount
                </SortableHead>
              )}
              {cols.isVisible("settled") && (
                <SortableHead sortKey="settled" sort={sort} onToggle={toggle} className="text-right">
                  Settled
                </SortableHead>
              )}
              {cols.isVisible("status") && (
                <SortableHead sortKey="status" sort={sort} onToggle={toggle}>
                  Status
                </SortableHead>
              )}
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {pageItems.map((d) => {
              const settled = settledOf(d.id);
              const status = dueStatusFromSettled(d, settled);
              return (
                <TableRow
                  key={d.id}
                  onClick={() => setViewing(d)}
                  className="cursor-pointer"
                >
                  {cols.isVisible("title") && (
                    <TableCell className="font-medium">{d.title}</TableCell>
                  )}
                  {cols.isVisible("direction") && (
                    <TableCell>
                      <Badge variant={d.direction === "receivable" ? "success" : "warning"}>
                        {d.direction}
                      </Badge>
                    </TableCell>
                  )}
                  {cols.isVisible("contact") && (
                    <TableCell>{d.contactId ? contactsById[d.contactId]?.name ?? "—" : "—"}</TableCell>
                  )}
                  {cols.isVisible("dueDate") && (
                    <TableCell className="whitespace-nowrap">{formatDate(toDate(d.dueDate))}</TableCell>
                  )}
                  {cols.isVisible("amount") && (
                    <TableCell className="text-right tabular-nums">
                      {formatMoney(d.amount, currency)}
                    </TableCell>
                  )}
                  {cols.isVisible("settled") && (
                    <TableCell className="text-right tabular-nums">
                      {formatMoney(settled, currency)}
                    </TableCell>
                  )}
                  {cols.isVisible("status") && (
                    <TableCell>
                      <Badge variant={statusVariant(status)}>{status}</Badge>
                    </TableCell>
                  )}
                  <TableCell>
                    <RowActions actions={rowActions(d)} />
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </ResizableTable>
      )}

      {sorted.length > 0 && <Pagination state={pagination} noun="dues" />}

      {viewing && (
        <DueDetail
          due={viewing}
          currency={currency}
          settled={settledOf(viewing.id)}
          contactName={viewing.contactId ? contactsById[viewing.contactId]?.name ?? "—" : "—"}
          accountName={viewing.accountId ? accountsById[viewing.accountId]?.name ?? "—" : "—"}
          actions={rowActions(viewing)}
          onClose={() => setViewing(null)}
        />
      )}

      {editing && activeWorkspaceId && (
        <DueDialog
          workspaceId={activeWorkspaceId}
          due={editing === "new" ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={() =>
            toast({ title: editing === "new" ? "Due created" : "Due updated", variant: "success" })
          }
        />
      )}

      {paying && (
        <TransactionFormDialog
          open
          onClose={() => setPaying(null)}
          onSubmit={handlePay}
          title={`Record payment: ${paying.title}`}
          initial={{
            presetContactId: paying.contactId,
            presetAccountId: paying.accountId,
            presetLines: [
              {
                lineId: `due_${Date.now()}`,
                type: paying.direction === "payable" ? "expense" : "income",
                amount: Math.max(0, paying.amount - settledOf(paying.id)),
              },
            ],
          }}
        />
      )}

      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title={`Delete "${toDelete?.title}"?`}
        description="This removes the due. Any transactions recorded against it are kept."
        destructive
        confirmLabel="Delete"
        onConfirm={async () => {
          if (toDelete) {
            await deleteDue(toDelete.id);
            setViewing(null);
            toast({ title: "Due deleted", variant: "success" });
          }
        }}
      />
    </div>
  );
}

function DueFilterSelect({
  value,
  onChange,
  allLabel,
  options,
}: {
  value: string;
  onChange: (v: string) => void;
  allLabel: string;
  options: { value: string; label: string }[];
}) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="__all">{allLabel}</SelectItem>
        {options.map((o) => (
          <SelectItem key={o.value} value={o.value}>
            {o.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

function statusVariant(status: Due["status"]) {
  return status === "settled"
    ? "success"
    : status === "partial"
      ? "warning"
      : status === "cancelled"
        ? "outline"
        : "secondary";
}

function DueDetail({
  due,
  currency,
  settled,
  contactName,
  accountName,
  actions,
  onClose,
}: {
  due: Due;
  currency: string;
  settled: number;
  contactName: string;
  accountName: string;
  actions: RowAction[];
  onClose: () => void;
}) {
  const status = dueStatusFromSettled(due, settled);
  const fields: DetailField[] = [
    { label: "Direction", value: due.direction },
    { label: "Status", value: status },
    { label: "Due date", value: formatDate(toDate(due.dueDate)) },
    { label: "Amount", value: formatMoney(due.amount, currency) },
    { label: "Settled", value: formatMoney(settled, currency) },
    { label: "Remaining", value: formatMoney(Math.max(0, due.amount - settled), currency) },
    { label: "Contact", value: contactName, hidden: !due.contactId },
    { label: "Account", value: accountName, hidden: !due.accountId },
  ];
  return (
    <DetailDialog
      open
      onClose={onClose}
      title={due.title}
      fields={fields}
      actions={actions}
      entityId={due.id}
      audit={{
        createdBy: due.createdBy,
        createdAt: due.createdAt,
        updatedBy: due.updatedBy,
        updatedAt: due.updatedAt,
      }}
    />
  );
}

function DueDialog({
  workspaceId,
  due,
  onClose,
  onSaved,
}: {
  workspaceId: string;
  due: Due | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { contacts, accounts } = useData();
  const [direction, setDirection] = useState<DueDirection>(due?.direction ?? "payable");
  const [title, setTitle] = useState(due?.title ?? "");
  const [amount, setAmount] = useState(String(due?.amount ?? 0));
  const [dueDate, setDueDate] = useState(
    due ? toDate(due.dueDate).toISOString().slice(0, 10) : new Date().toISOString().slice(0, 10),
  );
  const [contactId, setContactId] = useState(due?.contactId ?? "");
  const [accountId, setAccountId] = useState(due?.accountId ?? "");
  const [busy, setBusy] = useState(false);

  async function save() {
    if (!title.trim()) return;
    setBusy(true);
    try {
      if (due) {
        await updateDue(due.id, {
          direction,
          title: title.trim(),
          amount: Number(amount) || 0,
          dueDate: Timestamp.fromDate(new Date(dueDate)) as never,
          contactId: contactId || undefined,
          accountId: accountId || undefined,
        });
      } else {
        await createDue(workspaceId, {
          direction,
          title: title.trim(),
          amount: Number(amount) || 0,
          dueDate: Timestamp.fromDate(new Date(dueDate)) as never,
          contactId: contactId || undefined,
          accountId: accountId || undefined,
        });
      }
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
          <DialogTitle>{due ? "Edit due" : "New due"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Direction</Label>
              <Select value={direction} onValueChange={(v) => setDirection(v as DueDirection)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="payable">Payable (bill)</SelectItem>
                  <SelectItem value="receivable">Receivable</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Due date</Label>
              <Input type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>Title</Label>
            <Input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Electricity bill"
            />
          </div>
          <div className="space-y-1.5">
            <Label>Amount</Label>
            <Input type="number" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Contact (optional)</Label>
              <Select value={contactId || "__none"} onValueChange={(v) => setContactId(v === "__none" ? "" : v)}>
                <SelectTrigger>
                  <SelectValue placeholder="None" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none">None</SelectItem>
                  {contacts.map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Account (optional)</Label>
              <Select value={accountId || "__none"} onValueChange={(v) => setAccountId(v === "__none" ? "" : v)}>
                <SelectTrigger>
                  <SelectValue placeholder="None" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none">None</SelectItem>
                  {accounts.map((a) => (
                    <SelectItem key={a.id} value={a.id}>
                      {a.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !title.trim()}>
            {busy ? "Saving…" : due ? "Save changes" : "Create due"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
