// Shared money between workspace members — split costs and settle up
// (Splitwise-style). Member balances are derived from the `sharedExpenses`
// log; "Settle up" records a settlement payment. This ledger is separate from
// account balances — it tracks who-owes-whom among members, not bank money.

import { useMemo, useState } from "react";
import { ArrowRight, Plus, Check, Pencil, Trash2 } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useAuth } from "@/auth/AuthProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import {
  createSharedExpense,
  deleteSharedExpense,
  updateSharedExpense,
  type SharedExpenseInput,
} from "@/data/mutations";
import { memberBalances, simplifyDebts, toDate } from "@/lib/derive";
import { roundMoney } from "@/lib/txn";
import { cn, formatDate, formatMoney } from "@/lib/utils";
import { PageHeader } from "@/components/PageHeader";
import { RowActions, type RowAction } from "@/components/RowActions";
import { SortableHead } from "@/components/SortableHead";
import { ColumnsMenu } from "@/components/ColumnsMenu";
import { Toolbar } from "@/components/Toolbar";
import { DetailDialog, type DetailField } from "@/components/DetailDialog";
import { useColumnPrefs, type ColumnDef } from "@/lib/useColumnPrefs";
import { useSort, type SortAccessor } from "@/lib/useSort";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
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
import { EmptyState, ErrorState, LoadingState } from "@/components/states";
import { useToast } from "@/components/ui/toast";
import type { Membership, SharedExpense } from "@/types/models";

interface Member {
  uid: string;
  name: string;
}

function memberName(m: Membership): string {
  return m.displayName || m.email || `User ${m.uid.slice(0, 6)}`;
}

type SortKey = "description" | "paidBy" | "date" | "amount";
type ColKey = "description" | "paidBy" | "date" | "split" | "amount";

const COLUMNS: ColumnDef<ColKey>[] = [
  { key: "description", label: "Description", defaultVisible: true, locked: true },
  { key: "paidBy", label: "Paid by", defaultVisible: true },
  { key: "date", label: "Date", defaultVisible: true },
  { key: "split", label: "Split", defaultVisible: false },
  { key: "amount", label: "Amount", defaultVisible: true },
];

export function Shared() {
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { firebaseUser } = useAuth();
  const { sharedExpenses, members, loading, error } = useData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const canAdd = can("transactions.create");
  const canEdit = can("transactions.edit");
  const canDelete = can("transactions.delete");
  const myUid = firebaseUser?.uid ?? "";

  const [search, setSearch] = useState("");
  const [editing, setEditing] = useState<SharedExpense | "new" | null>(null);
  const [settle, setSettle] = useState<{ from: Member; to: Member; amount: number } | null>(null);
  const [toDelete, setToDelete] = useState<SharedExpense | null>(null);
  const [viewing, setViewing] = useState<SharedExpense | null>(null);

  // The current user's own name comes from auth, which always has it — even if
  // their membership doc predates denormalized identity.
  const myName = firebaseUser?.displayName || firebaseUser?.email || "You";

  const memberList: Member[] = useMemo(
    () => members.map((m) => ({ uid: m.uid, name: m.uid === myUid ? myName : memberName(m) })),
    [members, myUid, myName],
  );

  const balances = useMemo(() => memberBalances(sharedExpenses), [sharedExpenses]);
  const transfers = useMemo(() => simplifyDebts(balances), [balances]);

  // Resolve a uid to a display name from live data (re-resolved each render, so
  // it fixes records whose denormalized name was stale), falling back to the
  // name stored on the record, then a generic label.
  const nameForUid = (uid: string, fallback?: string) =>
    uid === myUid ? myName : (memberList.find((m) => m.uid === uid)?.name ?? fallback ?? "Member");

  const label = (uid: string, fallback?: string) =>
    nameForUid(uid, fallback) + (uid === myUid ? " (you)" : "");

  const cols = useColumnPrefs<ColKey>("sharedExpenses", COLUMNS);

  const filtered = useMemo(
    () =>
      sharedExpenses.filter((e) => {
        if (!search) return true;
        const hay = `${e.description} ${nameForUid(e.paidBy, e.paidByName)}`.toLowerCase();
        return hay.includes(search.toLowerCase());
      }),
    // nameForUid depends on memberList; recompute when those change
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [sharedExpenses, search, memberList],
  );

  const accessors: Record<SortKey, SortAccessor<SharedExpense>> = useMemo(
    () => ({
      description: (e) => e.description,
      paidBy: (e) => nameForUid(e.paidBy, e.paidByName),
      date: (e) => toDate(e.date),
      amount: (e) => e.amount,
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [memberList],
  );
  const { sorted, sort, toggle } = useSort(filtered, accessors, {
    key: "date",
    direction: "desc",
  });

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  function rowActions(e: SharedExpense): RowAction[] {
    return [
      { label: "Edit", icon: Pencil, onSelect: () => setEditing(e), hidden: !canEdit },
      {
        label: "Delete",
        icon: Trash2,
        onSelect: () => setToDelete(e),
        destructive: true,
        separatorBefore: true,
        hidden: !canDelete,
      },
    ];
  }

  return (
    <div>
      <PageHeader
        title="Shared"
        primaryAction={{
          label: "Add shared expense",
          icon: Plus,
          onClick: () => setEditing("new"),
          hidden: !canAdd,
        }}
      />

      {/* Balances */}
      <Card className="mb-4">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">Who owes whom</CardTitle>
        </CardHeader>
        <CardContent className="pt-0">
          {transfers.length === 0 ? (
            <p className="text-xs text-muted-foreground">All settled up. 🎉</p>
          ) : (
            <div className="space-y-1.5">
              {transfers.map((t, i) => (
                <div
                  key={`${t.fromUid}-${t.toUid}-${i}`}
                  className="flex items-center justify-between gap-2 text-xs"
                >
                  <span className="flex min-w-0 items-center gap-1.5">
                    <span className="truncate font-medium">{label(t.fromUid, t.fromName)}</span>
                    <ArrowRight className="h-3 w-3 shrink-0 text-muted-foreground" />
                    <span className="truncate font-medium">{label(t.toUid, t.toName)}</span>
                  </span>
                  <span className="flex shrink-0 items-center gap-2">
                    <span className="tabular-nums">{formatMoney(t.amount, currency)}</span>
                    {canAdd && (
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-7 px-2 text-xs"
                        onClick={() =>
                          setSettle({
                            from: { uid: t.fromUid, name: t.fromName },
                            to: { uid: t.toUid, name: t.toName },
                            amount: t.amount,
                          })
                        }
                      >
                        Settle up
                      </Button>
                    )}
                  </span>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Toolbar search={search} onSearch={setSearch} placeholder="Search description / payer…">
        <ColumnsMenu
          columns={cols.columns}
          isVisible={cols.isVisible}
          toggle={cols.toggle}
          reset={cols.reset}
        />
      </Toolbar>

      {/* History */}
      {sorted.length === 0 ? (
        <EmptyState
          title={search ? "No matches" : "Nothing shared yet"}
          hint={search ? undefined : "Add a shared expense to start tracking who owes whom."}
          action={
            canAdd && !search && (
              <Button onClick={() => setEditing("new")}>Add shared expense</Button>
            )
          }
        />
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              {cols.isVisible("description") && (
                <SortableHead sortKey="description" sort={sort} onToggle={toggle}>
                  Description
                </SortableHead>
              )}
              {cols.isVisible("paidBy") && (
                <SortableHead sortKey="paidBy" sort={sort} onToggle={toggle}>
                  Paid by
                </SortableHead>
              )}
              {cols.isVisible("date") && (
                <SortableHead sortKey="date" sort={sort} onToggle={toggle}>
                  Date
                </SortableHead>
              )}
              {cols.isVisible("split") && <TableHead>Split</TableHead>}
              {cols.isVisible("amount") && (
                <SortableHead sortKey="amount" sort={sort} onToggle={toggle} className="text-right">
                  Amount
                </SortableHead>
              )}
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {sorted.map((e) => (
              <TableRow key={e.id} onClick={() => setViewing(e)} className="cursor-pointer">
                {cols.isVisible("description") && (
                  <TableCell className="font-medium">
                    <span className="flex items-center gap-2">
                      <span className="truncate">{e.description}</span>
                      {e.kind === "settlement" && (
                        <Badge variant="secondary" className="shrink-0">
                          settlement
                        </Badge>
                      )}
                    </span>
                  </TableCell>
                )}
                {cols.isVisible("paidBy") && (
                  <TableCell className="text-muted-foreground">
                    {nameForUid(e.paidBy, e.paidByName)}
                  </TableCell>
                )}
                {cols.isVisible("date") && (
                  <TableCell className="text-muted-foreground">
                    {formatDate(toDate(e.date))}
                  </TableCell>
                )}
                {cols.isVisible("split") && (
                  <TableCell className="text-muted-foreground">
                    {e.kind === "settlement" ? "—" : `${e.splits.length} ways`}
                  </TableCell>
                )}
                {cols.isVisible("amount") && (
                  <TableCell className="text-right tabular-nums font-medium">
                    {formatMoney(e.amount, currency)}
                  </TableCell>
                )}
                <TableCell>
                  <RowActions actions={rowActions(e)} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      {viewing && (
        <SharedExpenseDetailDialog
          expense={viewing}
          currency={currency}
          nameForUid={nameForUid}
          onClose={() => setViewing(null)}
          onEdit={canEdit ? (e) => setEditing(e) : undefined}
          onDelete={canDelete ? (e) => setToDelete(e) : undefined}
        />
      )}

      {editing && activeWorkspaceId && (
        <ExpenseDialog
          expense={editing === "new" ? null : editing}
          members={memberList}
          defaultPayer={myUid}
          currency={currency}
          onClose={() => setEditing(null)}
          onSaved={() => toast({ title: "Saved", variant: "success" })}
        />
      )}

      {settle && activeWorkspaceId && (
        <SettleDialog
          from={settle.from}
          to={settle.to}
          suggested={settle.amount}
          currency={currency}
          onClose={() => setSettle(null)}
          onSaved={() => toast({ title: "Settlement recorded", variant: "success" })}
        />
      )}

      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title="Delete this entry?"
        destructive
        confirmLabel="Delete"
        onConfirm={async () => {
          if (toDelete) {
            await deleteSharedExpense(toDelete.id);
            toast({ title: "Deleted", variant: "success" });
          }
        }}
      />
    </div>
  );
}

function SharedExpenseDetailDialog({
  expense,
  currency,
  nameForUid,
  onClose,
  onEdit,
  onDelete,
}: {
  expense: SharedExpense;
  currency: string;
  nameForUid: (uid: string, fallback?: string) => string;
  onClose: () => void;
  onEdit?: (e: SharedExpense) => void;
  onDelete?: (e: SharedExpense) => void;
}) {
  const fields: DetailField[] = [
    {
      label: "Type",
      value: expense.kind === "settlement" ? "Settlement" : "Shared expense",
    },
    { label: "Paid by", value: nameForUid(expense.paidBy, expense.paidByName) },
    { label: "Date", value: formatDate(toDate(expense.date)) },
    {
      label: "Amount",
      value: <span className="tabular-nums">{formatMoney(expense.amount, currency)}</span>,
    },
  ];

  const actions: RowAction[] = [
    onEdit && { label: "Edit", icon: Pencil, onSelect: () => onEdit(expense) },
    onDelete && {
      label: "Delete",
      icon: Trash2,
      onSelect: () => onDelete(expense),
      destructive: true,
      separatorBefore: true,
    },
  ].filter(Boolean) as RowAction[];

  return (
    <DetailDialog
      open
      onClose={onClose}
      title={expense.description}
      fields={fields}
      actions={actions}
      entityId={expense.id}
      audit={{
        createdBy: expense.createdBy,
        createdAt: expense.createdAt,
        updatedBy: expense.updatedBy,
        updatedAt: expense.updatedAt,
      }}
    >
      <div className="mt-2">
        <p className="mb-2 text-sm font-medium">
          {expense.kind === "settlement" ? "Paid to" : "Split between"}
        </p>
        <div className="overflow-hidden rounded-md border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Member</TableHead>
                <TableHead className="text-right">Share</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {expense.splits.map((s) => (
                <TableRow key={s.uid}>
                  <TableCell>{nameForUid(s.uid, s.name)}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    {formatMoney(s.share, currency)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </div>
    </DetailDialog>
  );
}

function todayInput(): string {
  return new Date().toISOString().slice(0, 10);
}

function ExpenseDialog({
  expense,
  members,
  defaultPayer,
  currency,
  onClose,
  onSaved,
}: {
  expense: SharedExpense | null;
  members: Member[];
  defaultPayer: string;
  currency: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { activeWorkspaceId } = useWorkspace();
  const [description, setDescription] = useState(expense?.description ?? "");
  const [amount, setAmount] = useState(String(expense?.amount ?? ""));
  const [paidBy, setPaidBy] = useState(expense?.paidBy ?? defaultPayer ?? members[0]?.uid ?? "");
  const [dateStr, setDateStr] = useState(
    expense ? toDate(expense.date).toISOString().slice(0, 10) : todayInput(),
  );
  // selected participant uids (equal split). Defaults to all members.
  const [selected, setSelected] = useState<Set<string>>(
    () =>
      new Set(expense ? expense.splits.map((s) => s.uid) : members.map((m) => m.uid)),
  );
  const [busy, setBusy] = useState(false);

  const total = Number(amount) || 0;
  const participants = members.filter((m) => selected.has(m.uid));
  const valid = description.trim() && total > 0 && paidBy && participants.length > 0;

  function toggle(uid: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(uid)) next.delete(uid);
      else next.add(uid);
      return next;
    });
  }

  // Equal split with the rounding remainder absorbed by the first participant.
  function buildSplits(): SharedExpense["splits"] {
    const n = participants.length;
    const base = roundMoney(total / n);
    return participants.map((m, i) => ({
      uid: m.uid,
      name: m.name,
      share: i === 0 ? roundMoney(total - base * (n - 1)) : base,
    }));
  }

  async function save() {
    if (!valid || !activeWorkspaceId) return;
    setBusy(true);
    try {
      const payer = members.find((m) => m.uid === paidBy);
      const input: SharedExpenseInput = {
        kind: "expense",
        description: description.trim(),
        amount: roundMoney(total),
        date: new Date(dateStr),
        paidBy,
        paidByName: payer?.name ?? "Member",
        splits: buildSplits(),
      };
      if (expense) await updateSharedExpense(expense.id, input);
      else await createSharedExpense(activeWorkspaceId, input);
      onSaved();
      onClose();
    } finally {
      setBusy(false);
    }
  }

  const perHead = participants.length > 0 ? roundMoney(total / participants.length) : 0;

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>{expense ? "Edit shared expense" : "Add shared expense"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label>Description</Label>
            <Input
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Dinner, groceries…"
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Amount</Label>
              <Input
                type="number"
                min="0"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Date</Label>
              <Input type="date" value={dateStr} onChange={(e) => setDateStr(e.target.value)} />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>Paid by</Label>
            <Select value={paidBy} onValueChange={setPaidBy}>
              <SelectTrigger>
                <SelectValue placeholder="Who paid?" />
              </SelectTrigger>
              <SelectContent>
                {members.map((m) => (
                  <SelectItem key={m.uid} value={m.uid}>
                    {m.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <div className="flex items-center justify-between">
              <Label>Split equally between</Label>
              {participants.length > 0 && total > 0 && (
                <span className="text-xs text-muted-foreground">
                  {formatMoney(perHead, currency)} each
                </span>
              )}
            </div>
            <div className="max-h-44 space-y-1 overflow-y-auto rounded-md border p-1">
              {members.map((m) => {
                const on = selected.has(m.uid);
                return (
                  <button
                    type="button"
                    key={m.uid}
                    onClick={() => toggle(m.uid)}
                    className={cn(
                      "flex w-full items-center justify-between rounded px-2 py-1.5 text-sm",
                      on ? "bg-primary/10" : "hover:bg-muted",
                    )}
                  >
                    <span className="truncate">{m.name}</span>
                    <span
                      className={cn(
                        "flex h-4 w-4 items-center justify-center rounded border",
                        on ? "border-primary bg-primary text-primary-foreground" : "border-input",
                      )}
                    >
                      {on && <Check className="h-3 w-3" />}
                    </span>
                  </button>
                );
              })}
              {members.length === 0 && (
                <p className="px-2 py-1.5 text-sm text-muted-foreground">No members found.</p>
              )}
            </div>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !valid}>
            {busy ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function SettleDialog({
  from,
  to,
  suggested,
  currency,
  onClose,
  onSaved,
}: {
  from: Member;
  to: Member;
  suggested: number;
  currency: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { activeWorkspaceId } = useWorkspace();
  const [amount, setAmount] = useState(String(suggested));
  const [busy, setBusy] = useState(false);
  const value = Number(amount) || 0;

  async function save() {
    if (value <= 0 || !activeWorkspaceId) return;
    setBusy(true);
    try {
      // A settlement: `from` pays `to`. Payer fronts the amount; the recipient
      // is the sole participant, so the payer's debt to them is reduced.
      await createSharedExpense(activeWorkspaceId, {
        kind: "settlement",
        description: `${from.name} → ${to.name} settlement`,
        amount: roundMoney(value),
        date: new Date(),
        paidBy: from.uid,
        paidByName: from.name,
        splits: [{ uid: to.uid, name: to.name, share: roundMoney(value) }],
      });
      onSaved();
      onClose();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Settle up</DialogTitle>
        </DialogHeader>
        <p className="text-sm text-muted-foreground">
          Record a payment from <span className="font-medium text-foreground">{from.name}</span> to{" "}
          <span className="font-medium text-foreground">{to.name}</span>.
        </p>
        <div className="space-y-1.5">
          <Label>Amount ({currency})</Label>
          <Input
            type="number"
            min="0"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || value <= 0}>
            {busy ? "Saving…" : "Record settlement"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
