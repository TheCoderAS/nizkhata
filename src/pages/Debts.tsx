// Debts (§6.8). Obligations grouped by direction & purpose; create / edit /
// delete; settle via a repayment transaction (opens the multi-line form
// pre-seeded with a repayment line). Sortable headers, clickable rows -> detail
// modal, kebab row actions.

import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Plus, HandCoins, Pencil, Trash2, Users, ArrowLeftRight } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import {
  createDebtWithOpening,
  createTransaction,
  deleteDebt,
  updateDebt,
  type TransactionInput,
} from "@/data/mutations";
import { txnsByContact, contactDetailPath } from "@/lib/links";
import type { Debt, DebtDirection, DebtPurpose } from "@/types/models";
import { PageHeader } from "@/components/PageHeader";
import { TransactionFormDialog } from "@/components/TransactionForm";
import { RowActions, type RowAction } from "@/components/RowActions";
import { SortableHead } from "@/components/SortableHead";
import { DetailDialog, type DetailField } from "@/components/DetailDialog";
import { ColumnsMenu } from "@/components/ColumnsMenu";
import { ResizableTable } from "@/components/ResizableTable";
import { Toolbar } from "@/components/Toolbar";
import { useColumnPrefs, type ColumnDef } from "@/lib/useColumnPrefs";
import { useSort, type SortAccessor } from "@/lib/useSort";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
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
import { formatMoney } from "@/lib/utils";

const PURPOSE_LABELS: Record<DebtPurpose, string> = {
  loan: "Loan",
  custodial_savings: "Custodial savings",
  lending: "Lending",
  reimbursable: "Reimbursable",
  informal: "Informal",
  shared: "Shared",
};

type SortKey = "label" | "contact" | "purpose" | "status" | "outstanding";
type ColKey = "label" | "contact" | "purpose" | "status" | "outstanding";

const COLUMNS: ColumnDef<ColKey>[] = [
  { key: "label", label: "Label", defaultVisible: true, locked: true },
  { key: "contact", label: "Contact", defaultVisible: true },
  { key: "purpose", label: "Purpose", defaultVisible: false },
  { key: "status", label: "Status", defaultVisible: true },
  { key: "outstanding", label: "Outstanding", defaultVisible: true },
];

export function Debts() {
  const navigate = useNavigate();
  const { firebaseUser } = useAuth();
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { debts, contactsById, outstandingOf, loading, error } = useData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const manage = can("debts.manage");
  const canTxn = can("transactions.create");
  const canViewTxns = can("transactions.view");
  const canViewContacts = can("contacts.view");

  const [editing, setEditing] = useState<Debt | "new" | null>(null);
  const [viewing, setViewing] = useState<Debt | null>(null);
  const [settling, setSettling] = useState<Debt | null>(null);
  const [toDelete, setToDelete] = useState<Debt | null>(null);
  const [search, setSearch] = useState("");

  const cols = useColumnPrefs<ColKey>("debts", COLUMNS);

  if (loading) return <PageSkeleton />;
  if (error) return <ErrorState message={error} />;

  const matches = (d: Debt) => {
    if (!search) return true;
    const hay = `${d.label ?? ""} ${contactsById[d.contactId]?.name ?? ""} ${
      PURPOSE_LABELS[d.purpose]
    }`.toLowerCase();
    return hay.includes(search.toLowerCase());
  };
  // Shared-ledger reflections are managed in the Shared section, not here.
  const visible = debts.filter((d) => d.purpose !== "shared");
  const owed = visible.filter((d) => d.direction === "owed" && matches(d));
  const owe = visible.filter((d) => d.direction === "owe" && matches(d));

  function rowActions(d: Debt): RowAction[] {
    const outstanding = outstandingOf(d.id);
    return [
      {
        label: d.direction === "owed" ? "Record receipt" : "Record repayment",
        icon: HandCoins,
        onSelect: () => setSettling(d),
        hidden: !canTxn || d.status !== "open" || outstanding <= 0,
      },
      {
        label: "View contact",
        icon: Users,
        onSelect: () => navigate(contactDetailPath(d.contactId)),
        separatorBefore: true,
        hidden: !canViewContacts || !d.contactId,
      },
      {
        label: "View transactions",
        icon: ArrowLeftRight,
        onSelect: () => navigate(txnsByContact(d.contactId)),
        hidden: !canViewTxns || !d.contactId,
      },
      { label: "Edit", icon: Pencil, onSelect: () => setEditing(d), separatorBefore: true, hidden: !manage },
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

  async function handleSettle(input: TransactionInput) {
    if (!activeWorkspaceId || !firebaseUser) return;
    await createTransaction(activeWorkspaceId, firebaseUser.uid, input);
    if (settling) {
      const remaining = outstandingOf(settling.id) - Math.abs(input.totalAmount);
      if (remaining <= 0.005) await updateDebt(settling.id, { status: "settled" });
    }
    toast({ title: "Repayment recorded", variant: "success" });
  }

  return (
    <div>
      <PageHeader
        title="Debts"
        primaryAction={{
          label: "New debt",
          icon: Plus,
          onClick: () => setEditing("new"),
          hidden: !manage,
        }}
      />

      {visible.length > 0 && (
        <Toolbar search={search} onSearch={setSearch} placeholder="Search debts…">
          <ColumnsMenu columns={cols.columns} isVisible={cols.isVisible} toggle={cols.toggle} reset={cols.reset} hasCustomWidths={cols.hasCustomWidths} onResetWidths={cols.resetWidths} />
        </Toolbar>
      )}

      {visible.length === 0 ? (
        <EmptyState
          title="No debts yet"
          hint="Track money you owe or money owed to you."
          action={manage && <Button onClick={() => setEditing("new")}>New debt</Button>}
        />
      ) : (
        <div className="space-y-8">
          <DebtGroup
            title="They owe you"
            debts={owed}
            currency={currency}
            contactName={(id) => contactsById[id]?.name ?? "—"}
            outstandingOf={outstandingOf}
            onRowClick={setViewing}
            rowActions={rowActions}
            cols={cols}
          />
          <DebtGroup
            title="You owe"
            debts={owe}
            currency={currency}
            contactName={(id) => contactsById[id]?.name ?? "—"}
            outstandingOf={outstandingOf}
            onRowClick={setViewing}
            rowActions={rowActions}
            cols={cols}
          />
        </div>
      )}

      {viewing && (
        <DebtDetail
          debt={viewing}
          currency={currency}
          outstanding={outstandingOf(viewing.id)}
          contactName={contactsById[viewing.contactId]?.name ?? "—"}
          actions={rowActions(viewing)}
          onClose={() => setViewing(null)}
        />
      )}

      {editing && activeWorkspaceId && (
        <DebtDialog
          workspaceId={activeWorkspaceId}
          debt={editing === "new" ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={() =>
            toast({ title: editing === "new" ? "Debt created" : "Debt updated", variant: "success" })
          }
        />
      )}

      {settling && (
        <TransactionFormDialog
          open
          onClose={() => setSettling(null)}
          onSubmit={handleSettle}
          title={`Settle: ${settling.label ?? PURPOSE_LABELS[settling.purpose]}`}
          initial={{
            presetContactId: settling.contactId,
            lockContact: true,
            presetLines: [
              {
                lineId: `seed_${Date.now()}`,
                type: "repayment",
                amount: outstandingOf(settling.id),
                debtId: settling.id,
              },
            ],
          }}
        />
      )}

      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title={`Delete "${toDelete?.label ?? "debt"}"?`}
        description="Linked transactions keep their reference but this debt will no longer be tracked."
        destructive
        confirmLabel="Delete"
        onConfirm={async () => {
          if (toDelete) {
            await deleteDebt(toDelete.id);
            setViewing(null);
            toast({ title: "Debt deleted", variant: "success" });
          }
        }}
      />
    </div>
  );
}

function DebtGroup({
  title,
  debts,
  currency,
  contactName,
  outstandingOf,
  onRowClick,
  rowActions,
  cols,
}: {
  title: string;
  debts: Debt[];
  currency: string;
  contactName: (id: string) => string;
  outstandingOf: (id: string) => number;
  onRowClick: (d: Debt) => void;
  rowActions: (d: Debt) => RowAction[];
  cols: ReturnType<typeof useColumnPrefs<ColKey>>;
}) {
  const accessors: Record<SortKey, SortAccessor<Debt>> = {
    label: (d) => d.label ?? "",
    contact: (d) => contactName(d.contactId),
    purpose: (d) => PURPOSE_LABELS[d.purpose],
    status: (d) => d.status,
    outstanding: (d) => outstandingOf(d.id),
  };
  const { sorted, sort, toggle } = useSort(debts, accessors, {
    key: "label",
    direction: "asc",
  });

  if (debts.length === 0) return null;
  return (
    <div>
      <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
        {title}
      </h2>
      <ResizableTable prefs={cols} className="[&_td]:truncate">
        <TableHeader>
          <TableRow>
            {cols.isVisible("label") && (
              <SortableHead sortKey="label" sort={sort} onToggle={toggle}>
                Label
              </SortableHead>
            )}
            {cols.isVisible("contact") && (
              <SortableHead sortKey="contact" sort={sort} onToggle={toggle}>
                Contact
              </SortableHead>
            )}
            {cols.isVisible("purpose") && (
              <SortableHead sortKey="purpose" sort={sort} onToggle={toggle}>
                Purpose
              </SortableHead>
            )}
            {cols.isVisible("status") && (
              <SortableHead sortKey="status" sort={sort} onToggle={toggle}>
                Status
              </SortableHead>
            )}
            {cols.isVisible("outstanding") && (
              <SortableHead sortKey="outstanding" sort={sort} onToggle={toggle} className="text-right">
                Outstanding
              </SortableHead>
            )}
            <TableHead className="w-12" />
          </TableRow>
        </TableHeader>
        <TableBody>
          {sorted.map((d) => (
            <TableRow
              key={d.id}
              onClick={() => onRowClick(d)}
              className="cursor-pointer"
            >
              {cols.isVisible("label") && (
                <TableCell className="font-medium">{d.label ?? "—"}</TableCell>
              )}
              {cols.isVisible("contact") && (
                <TableCell>{contactName(d.contactId)}</TableCell>
              )}
              {cols.isVisible("purpose") && (
                <TableCell>
                  <Badge variant="secondary">{PURPOSE_LABELS[d.purpose]}</Badge>
                </TableCell>
              )}
              {cols.isVisible("status") && (
                <TableCell>
                  <Badge variant={d.status === "open" ? "warning" : "success"}>
                    {d.status}
                  </Badge>
                </TableCell>
              )}
              {cols.isVisible("outstanding") && (
                <TableCell className="text-right tabular-nums">
                  {formatMoney(outstandingOf(d.id), currency)}
                </TableCell>
              )}
              <TableCell>
                <RowActions actions={rowActions(d)} />
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </ResizableTable>
    </div>
  );
}

function DebtDetail({
  debt,
  currency,
  outstanding,
  contactName,
  actions,
  onClose,
}: {
  debt: Debt;
  currency: string;
  outstanding: number;
  contactName: string;
  actions: RowAction[];
  onClose: () => void;
}) {
  const fields: DetailField[] = [
    { label: "Contact", value: contactName },
    {
      label: "Direction",
      value: debt.direction === "owed" ? "They owe you" : "You owe them",
    },
    { label: "Purpose", value: PURPOSE_LABELS[debt.purpose] },
    { label: "Status", value: debt.status },
    { label: "Principal (reference)", value: formatMoney(debt.principal, currency) },
    { label: "Outstanding", value: formatMoney(outstanding, currency) },
    { label: "Note", value: debt.note ?? "—", block: true, hidden: !debt.note },
  ];
  return (
    <DetailDialog
      open
      onClose={onClose}
      title={debt.label ?? PURPOSE_LABELS[debt.purpose]}
      fields={fields}
      actions={actions}
      entityId={debt.id}
      audit={{
        createdBy: debt.createdBy,
        createdAt: debt.createdAt,
        updatedBy: debt.updatedBy,
        updatedAt: debt.updatedAt,
      }}
    />
  );
}

function DebtDialog({
  workspaceId,
  debt,
  onClose,
  onSaved,
}: {
  workspaceId: string;
  debt: Debt | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { firebaseUser } = useAuth();
  const { activeWorkspace } = useWorkspace();
  const { contacts, accounts } = useData();
  const fyStartMonth = activeWorkspace?.fyStartMonth ?? 4;
  const [contactId, setContactId] = useState(debt?.contactId ?? "");
  const [direction, setDirection] = useState<DebtDirection>(debt?.direction ?? "owe");
  const [purpose, setPurpose] = useState<DebtPurpose>(debt?.purpose ?? "loan");
  const [label, setLabel] = useState(debt?.label ?? "");
  const [note, setNote] = useState(debt?.note ?? "");
  // "Opening amount" seeds an opening-balance transaction on create.
  const [openingAmount, setOpeningAmount] = useState(String(debt?.principal ?? 0));
  const [accountId, setAccountId] = useState("__external"); // default External / none
  const [openingDate, setOpeningDate] = useState(new Date().toISOString().slice(0, 10));
  const [status, setStatus] = useState(debt?.status ?? "open");
  const [busy, setBusy] = useState(false);

  async function save() {
    if (!contactId) return;
    setBusy(true);
    try {
      if (debt) {
        // direction / purpose / contact are structural; allow label, note,
        // principal, and manual status (re-open / settle) edits.
        await updateDebt(debt.id, {
          label: label.trim() || undefined,
          note: note.trim() || undefined,
          principal: Number(openingAmount) || 0,
          status,
        });
      } else {
        const amount = Number(openingAmount) || 0;
        await createDebtWithOpening(
          workspaceId,
          firebaseUser?.uid ?? "",
          fyStartMonth,
          {
            contactId,
            direction,
            purpose,
            principal: amount,
            label: label.trim() || undefined,
            note: note.trim() || undefined,
          },
          {
            amount,
            accountId: accountId === "__external" ? undefined : accountId,
            date: new Date(openingDate),
          },
        );
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
          <DialogTitle>{debt ? "Edit debt" : "New debt"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label>Contact</Label>
            <Select value={contactId} onValueChange={setContactId} disabled={!!debt}>
              <SelectTrigger>
                <SelectValue placeholder="Select contact" />
              </SelectTrigger>
              <SelectContent>
                {contacts.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Direction</Label>
              <Select
                value={direction}
                onValueChange={(v) => setDirection(v as DebtDirection)}
                disabled={!!debt}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="owe">You owe them</SelectItem>
                  <SelectItem value="owed">They owe you</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Purpose</Label>
              <Select
                value={purpose}
                onValueChange={(v) => setPurpose(v as DebtPurpose)}
                disabled={!!debt}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(Object.keys(PURPOSE_LABELS) as DebtPurpose[]).map((p) => (
                    <SelectItem key={p} value={p}>
                      {PURPOSE_LABELS[p]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>Label</Label>
            <Input
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              placeholder="Car loan - HDFC"
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Opening amount</Label>
              <Input
                type="number"
                min="0"
                value={openingAmount}
                onChange={(e) => setOpeningAmount(e.target.value)}
              />
            </div>
            {debt ? (
              <div className="space-y-1.5">
                <Label>Status</Label>
                <Select value={status} onValueChange={(v) => setStatus(v as Debt["status"])}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="open">Open</SelectItem>
                    <SelectItem value="settled">Settled</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            ) : (
              <div className="space-y-1.5">
                <Label>Account</Label>
                <Select value={accountId} onValueChange={setAccountId}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__external">External / none</SelectItem>
                    {accounts.map((a) => (
                      <SelectItem key={a.id} value={a.id}>
                        {a.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}
          </div>
          {!debt && Number(openingAmount) > 0 && (
            <div className="space-y-1.5">
              <Label>Opening date</Label>
              <Input
                type="date"
                value={openingDate}
                onChange={(e) => setOpeningDate(e.target.value)}
              />
            </div>
          )}
          <div className="space-y-1.5">
            <Label>Note (optional)</Label>
            <Textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Any details about this debt…"
            />
          </div>
          {!debt && Number(openingAmount) > 0 && (
            <p className="text-xs text-muted-foreground">
              {accountId === "__external"
                ? "Records the debt only — no account balance is affected."
                : direction === "owe"
                  ? "Adds the opening amount to the selected account (money received)."
                  : "Deducts the opening amount from the selected account (money given out)."}
            </p>
          )}
          {debt && (
            <p className="text-xs text-muted-foreground">
              Contact, direction and purpose are fixed after creation to keep
              linked transactions consistent.
            </p>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !contactId}>
            {busy ? "Saving…" : debt ? "Save changes" : "Create debt"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
