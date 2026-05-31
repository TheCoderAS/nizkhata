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
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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

  const [editing, setEditing] = useState<SharedExpense | "new" | null>(null);
  const [settle, setSettle] = useState<{ from: Member; to: Member; amount: number } | null>(null);
  const [toDelete, setToDelete] = useState<SharedExpense | null>(null);

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

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

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

      <div className="mt-4" />

      {/* Balances */}
      <Card className="mb-6">
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Who owes whom</CardTitle>
        </CardHeader>
        <CardContent>
          {transfers.length === 0 ? (
            <p className="text-sm text-muted-foreground">All settled up. 🎉</p>
          ) : (
            <div className="space-y-2">
              {transfers.map((t, i) => (
                <div
                  key={`${t.fromUid}-${t.toUid}-${i}`}
                  className="flex items-center justify-between gap-2 text-sm"
                >
                  <span className="flex min-w-0 items-center gap-1.5">
                    <span className="truncate font-medium">{label(t.fromUid, t.fromName)}</span>
                    <ArrowRight className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
                    <span className="truncate font-medium">{label(t.toUid, t.toName)}</span>
                  </span>
                  <span className="flex shrink-0 items-center gap-2">
                    <span className="tabular-nums">{formatMoney(t.amount, currency)}</span>
                    {canAdd && (
                      <Button
                        size="sm"
                        variant="outline"
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

      {/* History */}
      {sharedExpenses.length === 0 ? (
        <EmptyState
          title="Nothing shared yet"
          hint="Add a shared expense to start tracking who owes whom."
          action={canAdd && <Button onClick={() => setEditing("new")}>Add shared expense</Button>}
        />
      ) : (
        <div className="space-y-2">
          {sharedExpenses.map((e) => (
            <Card key={e.id}>
              <CardContent className="flex items-start justify-between gap-3 py-3">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                    <span className="font-medium">{e.description}</span>
                    {e.kind === "settlement" && <Badge variant="secondary">settlement</Badge>}
                  </div>
                  <p className="mt-0.5 text-xs text-muted-foreground">
                    {nameForUid(e.paidBy, e.paidByName)} paid · {formatDate(toDate(e.date))}
                    {e.kind === "expense" && ` · split ${e.splits.length} ways`}
                  </p>
                </div>
                <div className="flex shrink-0 items-center gap-1">
                  <span className="tabular-nums">{formatMoney(e.amount, currency)}</span>
                  <RowActions
                    actions={[
                      {
                        label: "Edit",
                        icon: Pencil,
                        onSelect: () => setEditing(e),
                        hidden: !canEdit,
                      },
                      {
                        label: "Delete",
                        icon: Trash2,
                        onSelect: () => setToDelete(e),
                        destructive: true,
                        hidden: !canDelete,
                      },
                    ]}
                  />
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
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
