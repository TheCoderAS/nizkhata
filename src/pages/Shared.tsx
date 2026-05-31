// Shared — Splitwise-style sharing between real app users, ACROSS workspaces.
//
// A shared item is a cross-user proposal: I record my side immediately (I
// already paid), and the counterparty gets a to-do to accept (records a
// balance-only "I owe you") or reject (raises a conflict I resolve). Settlements
// work the same way and require the counterparty's acceptance. Balances are
// derived from accepted entries (+ my own pending expense claims). Partners are
// NOT workspace members and cannot see or enter my workspace.

import { useMemo, useState } from "react";
import { ArrowRight, Plus, Check, X, Inbox, UserPlus, AlertTriangle } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useAuth } from "@/auth/AuthProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { useSharedData } from "@/data/SharedDataProvider";
import {
  acceptSharedExpense,
  acceptSettlement,
  createSharedExpense,
  inviteSharedPartner,
  proposeSettlement,
  rejectSharedEntry,
  resolveConflict,
  withdrawSharedEntry,
  type SharedExpenseParticipant,
} from "@/data/sharedMutations";
import { sharedBalances, settleUpTransfers, toDate } from "@/lib/derive";
import { roundMoney } from "@/lib/txn";
import { cn, formatDate, formatMoney } from "@/lib/utils";
import { PageHeader } from "@/components/PageHeader";
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
import { EmptyState, ErrorState, LoadingState } from "@/components/states";
import { useToast } from "@/components/ui/toast";
import type { SharedEntry, Account } from "@/types/models";

function todayInput(): string {
  return new Date().toISOString().slice(0, 10);
}

interface Partner {
  uid: string;
  name: string;
  connectionId: string;
}

export function Shared() {
  const { activeWorkspaceId, activeWorkspace } = useWorkspace();
  const { firebaseUser } = useAuth();
  const { accounts, categories, contacts, debts, transactions, loading: wsLoading } = useData();
  const { connections, entries, sentInvites, loading: sharedLoading, error } = useSharedData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const fyStartMonth = activeWorkspace?.fyStartMonth ?? 4;
  const myUid = firebaseUser?.uid ?? "";

  const [invite, setInvite] = useState(false);
  const [adding, setAdding] = useState(false);
  const [settle, setSettle] = useState<{ partner: Partner; amount: number } | null>(null);
  const [conflict, setConflict] = useState<SharedEntry | null>(null);

  const partners: Partner[] = useMemo(
    () =>
      connections.map((c) => {
        const other = c.uids.find((u) => u !== myUid) ?? myUid;
        return { uid: other, name: c.names[other] ?? "Partner", connectionId: c.id };
      }),
    [connections, myUid],
  );

  const balances = useMemo(() => sharedBalances(myUid, entries), [myUid, entries]);
  const transfers = useMemo(() => settleUpTransfers(myUid, balances), [myUid, balances]);

  // Inbox: entries awaiting my response.
  const inbox = useMemo(
    () => entries.filter((e) => (e.pendingForUids ?? []).includes(myUid)),
    [entries, myUid],
  );
  // Conflicts: entries I created that were rejected and not yet resolved.
  const conflicts = useMemo(
    () => entries.filter((e) => e.creatorUid === myUid && e.status === "rejected" && !e.resolved),
    [entries, myUid],
  );

  const partnerName = (uid: string) =>
    uid === myUid ? "You" : (partners.find((p) => p.uid === uid)?.name ?? "Partner");

  if (wsLoading || sharedLoading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  const pendingInvites = sentInvites.filter((i) => i.status === "pending");

  async function onAccept(entry: SharedEntry, accountId?: string) {
    if (!activeWorkspaceId || !firebaseUser) return;
    const common = {
      entry,
      me: firebaseUser,
      workspaceId: activeWorkspaceId,
      fyStartMonth,
      contacts,
      debts,
    };
    if (entry.kind === "settlement") {
      await acceptSettlement({ ...common, accountId });
    } else {
      await acceptSharedExpense(common);
    }
    toast({ title: "Accepted", variant: "success" });
  }

  async function onReject(entry: SharedEntry) {
    await rejectSharedEntry(entry);
    toast({ title: "Rejected", variant: "success" });
  }

  return (
    <div>
      <PageHeader
        title="Shared"
        primaryAction={{
          label: "Add shared expense",
          icon: Plus,
          onClick: () => setAdding(true),
          hidden: partners.length === 0,
        }}
      />

      {/* Partners + invite */}
      <Card className="mb-4">
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-sm font-medium">Partners</CardTitle>
          <Button size="sm" variant="outline" className="h-7 px-2 text-xs" onClick={() => setInvite(true)}>
            <UserPlus className="mr-1 h-3 w-3" /> Invite
          </Button>
        </CardHeader>
        <CardContent className="pt-0">
          {partners.length === 0 ? (
            <p className="text-xs text-muted-foreground">
              No partners yet. Invite someone by email to start sharing.
            </p>
          ) : (
            <div className="flex flex-wrap gap-1.5">
              {partners.map((p) => (
                <Badge key={p.uid} variant="secondary">
                  {p.name}
                </Badge>
              ))}
            </div>
          )}
          {pendingInvites.length > 0 && (
            <p className="mt-2 text-xs text-muted-foreground">
              Pending invites: {pendingInvites.map((i) => i.toEmail).join(", ")}
            </p>
          )}
        </CardContent>
      </Card>

      {/* Conflicts */}
      {conflicts.length > 0 && (
        <Card className="mb-4 border-destructive/50">
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm font-medium text-destructive">
              <AlertTriangle className="h-4 w-4" /> Rejected — needs resolution
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-1.5 pt-0">
            {conflicts.map((e) => (
              <div key={e.id} className="flex items-center justify-between gap-2 text-xs">
                <span className="min-w-0 truncate">
                  {partnerName(e.counterpartyUid)} rejected{" "}
                  <span className="font-medium">{e.description}</span> ·{" "}
                  {formatMoney(e.amount, currency)}
                </span>
                <Button
                  size="sm"
                  variant="outline"
                  className="h-7 shrink-0 px-2 text-xs"
                  onClick={() => setConflict(e)}
                >
                  Resolve
                </Button>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {/* Inbox */}
      {inbox.length > 0 && (
        <Card className="mb-4 border-primary/40">
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm font-medium">
              <Inbox className="h-4 w-4" /> To review ({inbox.length})
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 pt-0">
            {inbox.map((e) => (
              <InboxRow
                key={e.id}
                entry={e}
                currency={currency}
                payerName={partnerName(e.payerUid)}
                accounts={accounts}
                onAccept={onAccept}
                onReject={onReject}
              />
            ))}
          </CardContent>
        </Card>
      )}

      {/* Who owes whom */}
      <Card className="mb-4">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">Who owes whom</CardTitle>
        </CardHeader>
        <CardContent className="pt-0">
          {transfers.length === 0 ? (
            <p className="text-xs text-muted-foreground">All settled up. 🎉</p>
          ) : (
            <div className="space-y-1.5">
              {transfers.map((t, i) => {
                const partner = partners.find((p) => p.uid === t.fromUid || p.uid === t.toUid);
                const iOwe = t.fromUid === myUid;
                return (
                  <div
                    key={`${t.fromUid}-${t.toUid}-${i}`}
                    className="flex items-center justify-between gap-2 text-xs"
                  >
                    <span className="flex min-w-0 items-center gap-1.5">
                      <span className="truncate font-medium">{t.fromName}</span>
                      <ArrowRight className="h-3 w-3 shrink-0 text-muted-foreground" />
                      <span className="truncate font-medium">{t.toName}</span>
                    </span>
                    <span className="flex shrink-0 items-center gap-2">
                      <span className="tabular-nums">{formatMoney(t.amount, currency)}</span>
                      {iOwe && partner && (
                        <Button
                          size="sm"
                          variant="outline"
                          className="h-7 px-2 text-xs"
                          onClick={() => setSettle({ partner, amount: t.amount })}
                        >
                          Settle up
                        </Button>
                      )}
                    </span>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* History */}
      {entries.length === 0 ? (
        <EmptyState
          title="Nothing shared yet"
          hint={
            partners.length === 0
              ? "Invite a partner by email, then add a shared expense."
              : "Add a shared expense to start tracking who owes whom."
          }
        />
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Description</TableHead>
              <TableHead>With</TableHead>
              <TableHead>Date</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="text-right">Amount</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {entries.map((e) => {
              const other = e.creatorUid === myUid ? e.counterpartyUid : e.creatorUid;
              return (
                <TableRow key={e.id}>
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
                  <TableCell className="text-muted-foreground">{partnerName(other)}</TableCell>
                  <TableCell className="text-muted-foreground">{formatDate(toDate(e.date))}</TableCell>
                  <TableCell>
                    <StatusBadge entry={e} myUid={myUid} />
                  </TableCell>
                  <TableCell className="text-right tabular-nums font-medium">
                    {formatMoney(e.amount, currency)}
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      )}

      {invite && firebaseUser && (
        <InviteDialog
          onClose={() => setInvite(false)}
          onInvite={async (email) => {
            await inviteSharedPartner(firebaseUser, email);
            toast({ title: "Invite sent", variant: "success" });
          }}
        />
      )}

      {adding && activeWorkspaceId && firebaseUser && (
        <AddExpenseDialog
          partners={partners}
          accounts={accounts}
          categories={categories.filter((c) => c.kind === "expense")}
          currency={currency}
          onClose={() => setAdding(false)}
          onSave={async (data) => {
            await createSharedExpense({
              me: firebaseUser,
              workspaceId: activeWorkspaceId,
              fyStartMonth,
              accountId: data.accountId,
              description: data.description,
              date: data.date,
              myShare: data.myShare,
              myCategoryId: data.myCategoryId,
              participants: data.participants,
              contacts,
              debts,
            });
            toast({ title: "Shared expense recorded", variant: "success" });
          }}
        />
      )}

      {settle && activeWorkspaceId && firebaseUser && (
        <SettleDialog
          partner={settle.partner}
          suggested={settle.amount}
          accounts={accounts}
          currency={currency}
          onClose={() => setSettle(null)}
          onSave={async (amount, accountId) => {
            await proposeSettlement({
              me: firebaseUser,
              counterpartyUid: settle.partner.uid,
              counterpartyName: settle.partner.name,
              connectionId: settle.partner.connectionId,
              amount,
              description: `Settlement to ${settle.partner.name}`,
              date: new Date(),
              workspaceId: activeWorkspaceId,
              fyStartMonth,
              accountId,
              contacts,
              debts,
            });
            toast({ title: "Settlement proposed", variant: "success" });
          }}
        />
      )}

      {conflict && activeWorkspaceId && (
        <ConflictDialog
          entry={conflict}
          categories={categories.filter((c) => c.kind === "expense")}
          onClose={() => setConflict(null)}
          onResolve={async (mode, categoryId) => {
            const refl = transactions.find((t) => t.sharedEntryId === conflict.id);
            const acct =
              refl?.accountId && refl.accountId !== "__external__"
                ? refl.accountId
                : (accounts[0]?.id ?? "");
            await resolveConflict({
              entry: conflict,
              mode,
              reflectionTxnId: refl?.id ?? "",
              myCategoryId: categoryId,
              fyStartMonth,
              date: toDate(conflict.date),
              accountId: acct,
              workspaceId: activeWorkspaceId,
            });
            toast({ title: "Conflict resolved", variant: "success" });
          }}
          onWithdraw={async () => {
            const refl = transactions.find((t) => t.sharedEntryId === conflict.id);
            await withdrawSharedEntry(conflict, refl?.id ?? null);
            toast({ title: "Withdrawn", variant: "success" });
          }}
        />
      )}
    </div>
  );
}

function StatusBadge({ entry, myUid }: { entry: SharedEntry; myUid: string }) {
  if (entry.status === "accepted") return <Badge variant="secondary">accepted</Badge>;
  if (entry.status === "rejected") return <Badge variant="destructive">rejected</Badge>;
  const mine = entry.creatorUid === myUid;
  return <Badge variant="outline">{mine ? "awaiting them" : "needs your response"}</Badge>;
}

function InboxRow({
  entry,
  currency,
  payerName,
  accounts,
  onAccept,
  onReject,
}: {
  entry: SharedEntry;
  currency: string;
  payerName: string;
  accounts: Account[];
  onAccept: (e: SharedEntry, accountId?: string) => Promise<void>;
  onReject: (e: SharedEntry) => Promise<void>;
}) {
  const [busy, setBusy] = useState(false);
  // Accepting a settlement records a real inflow → pick an account.
  const [accountId, setAccountId] = useState(accounts[0]?.id ?? "");
  const isSettlement = entry.kind === "settlement";

  async function act(fn: () => Promise<void>) {
    setBusy(true);
    try {
      await fn();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="rounded-md border p-2">
      <div className="flex items-center justify-between gap-2 text-xs">
        <span className="min-w-0">
          <span className="font-medium">{entry.description}</span>
          <span className="text-muted-foreground">
            {" "}
            · {isSettlement ? `${payerName} paid you` : `${payerName} paid`} ·{" "}
            {formatMoney(entry.amount, currency)}
          </span>
        </span>
        {isSettlement && <Badge variant="secondary">settlement</Badge>}
      </div>
      <div className="mt-2 flex items-center gap-2">
        {isSettlement && (
          <Select value={accountId} onValueChange={setAccountId}>
            <SelectTrigger className="h-7 w-40 text-xs">
              <SelectValue placeholder="Into account" />
            </SelectTrigger>
            <SelectContent>
              {accounts.map((a) => (
                <SelectItem key={a.id} value={a.id}>
                  {a.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        )}
        <Button
          size="sm"
          className="h-7 px-2 text-xs"
          disabled={busy || (isSettlement && !accountId)}
          onClick={() => void act(() => onAccept(entry, isSettlement ? accountId : undefined))}
        >
          <Check className="mr-1 h-3 w-3" /> Accept
        </Button>
        <Button
          size="sm"
          variant="outline"
          className="h-7 px-2 text-xs"
          disabled={busy}
          onClick={() => void act(() => onReject(entry))}
        >
          <X className="mr-1 h-3 w-3" /> Reject
        </Button>
      </div>
    </div>
  );
}

function InviteDialog({
  onClose,
  onInvite,
}: {
  onClose: () => void;
  onInvite: (email: string) => Promise<void>;
}) {
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const valid = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim());

  async function save() {
    if (!valid) return;
    setBusy(true);
    try {
      await onInvite(email.trim());
      onClose();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Invite a partner</DialogTitle>
        </DialogHeader>
        <p className="text-sm text-muted-foreground">
          They'll be able to share expenses with you once they sign in. They cannot see or enter
          your workspace.
        </p>
        <div className="space-y-1.5">
          <Label>Email</Label>
          <Input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="friend@example.com"
          />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !valid}>
            {busy ? "Sending…" : "Send invite"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

interface AddExpenseData {
  description: string;
  date: Date;
  accountId: string;
  myShare: number;
  myCategoryId?: string;
  participants: SharedExpenseParticipant[];
}

function AddExpenseDialog({
  partners,
  accounts,
  categories,
  currency,
  onClose,
  onSave,
}: {
  partners: Partner[];
  accounts: Account[];
  categories: { id: string; name: string }[];
  currency: string;
  onClose: () => void;
  onSave: (data: AddExpenseData) => Promise<void>;
}) {
  const [description, setDescription] = useState("");
  const [amount, setAmount] = useState("");
  const [dateStr, setDateStr] = useState(todayInput());
  const [accountId, setAccountId] = useState(accounts[0]?.id ?? "");
  const [categoryId, setCategoryId] = useState(categories[0]?.id ?? "");
  const [includeMe, setIncludeMe] = useState(true);
  const [selected, setSelected] = useState<Set<string>>(() => new Set(partners.map((p) => p.uid)));
  const [busy, setBusy] = useState(false);

  const total = Number(amount) || 0;
  const chosen = partners.filter((p) => selected.has(p.uid));
  const splitCount = chosen.length + (includeMe ? 1 : 0);
  const perHead = splitCount > 0 ? roundMoney(total / splitCount) : 0;
  const valid = !!(description.trim() && total > 0 && accountId && chosen.length > 0);

  function toggle(uid: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(uid)) next.delete(uid);
      else next.add(uid);
      return next;
    });
  }

  async function save() {
    if (!valid) return;
    setBusy(true);
    try {
      // Equal split; the payer (me) absorbs any rounding remainder.
      const base = perHead;
      const participants: SharedExpenseParticipant[] = chosen.map((p) => ({
        counterpartyUid: p.uid,
        counterpartyName: p.name,
        connectionId: p.connectionId,
        share: base,
      }));
      const othersTotal = roundMoney(base * chosen.length);
      const myShare = includeMe ? roundMoney(total - othersTotal) : 0;
      await onSave({
        description: description.trim(),
        date: new Date(dateStr),
        accountId,
        myShare: myShare > 0 ? myShare : 0,
        myCategoryId: includeMe ? categoryId : undefined,
        participants,
      });
      onClose();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Add shared expense</DialogTitle>
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
              <Label>Total amount</Label>
              <Input type="number" min="0" value={amount} onChange={(e) => setAmount(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Date</Label>
              <Input type="date" value={dateStr} onChange={(e) => setDateStr(e.target.value)} />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label>Paid from</Label>
            <Select value={accountId} onValueChange={setAccountId}>
              <SelectTrigger>
                <SelectValue placeholder="Account" />
              </SelectTrigger>
              <SelectContent>
                {accounts.map((a) => (
                  <SelectItem key={a.id} value={a.id}>
                    {a.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <div className="flex items-center justify-between">
              <Label>Split equally between</Label>
              {splitCount > 0 && total > 0 && (
                <span className="text-xs text-muted-foreground">
                  {formatMoney(perHead, currency)} each
                </span>
              )}
            </div>
            <div className="max-h-44 space-y-1 overflow-y-auto rounded-md border p-1">
              <SplitToggle label="You" on={includeMe} onClick={() => setIncludeMe((v) => !v)} />
              {partners.map((p) => (
                <SplitToggle
                  key={p.uid}
                  label={p.name}
                  on={selected.has(p.uid)}
                  onClick={() => toggle(p.uid)}
                />
              ))}
            </div>
          </div>
          {includeMe && (
            <div className="space-y-1.5">
              <Label>My share category</Label>
              <Select value={categoryId} onValueChange={setCategoryId}>
                <SelectTrigger>
                  <SelectValue placeholder="Category" />
                </SelectTrigger>
                <SelectContent>
                  {categories.map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !valid}>
            {busy ? "Saving…" : "Record & request"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function SplitToggle({ label, on, onClick }: { label: string; on: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex w-full items-center justify-between rounded px-2 py-1.5 text-sm",
        on ? "bg-primary/10" : "hover:bg-muted",
      )}
    >
      <span className="truncate">{label}</span>
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
}

function SettleDialog({
  partner,
  suggested,
  accounts,
  currency,
  onClose,
  onSave,
}: {
  partner: Partner;
  suggested: number;
  accounts: Account[];
  currency: string;
  onClose: () => void;
  onSave: (amount: number, accountId: string) => Promise<void>;
}) {
  const [amount, setAmount] = useState(String(suggested));
  const [accountId, setAccountId] = useState(accounts[0]?.id ?? "");
  const [busy, setBusy] = useState(false);
  const value = Number(amount) || 0;
  const valid = !!(value > 0 && accountId);

  async function save() {
    if (!valid) return;
    setBusy(true);
    try {
      await onSave(roundMoney(value), accountId);
      onClose();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Settle up with {partner.name}</DialogTitle>
        </DialogHeader>
        <p className="text-sm text-muted-foreground">
          Records the payment from your account now; {partner.name} must accept it to record their
          side.
        </p>
        <div className="space-y-1.5">
          <Label>Amount ({currency})</Label>
          <Input type="number" min="0" value={amount} onChange={(e) => setAmount(e.target.value)} />
        </div>
        <div className="space-y-1.5">
          <Label>Paid from</Label>
          <Select value={accountId} onValueChange={setAccountId}>
            <SelectTrigger>
              <SelectValue placeholder="Account" />
            </SelectTrigger>
            <SelectContent>
              {accounts.map((a) => (
                <SelectItem key={a.id} value={a.id}>
                  {a.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !valid}>
            {busy ? "Saving…" : "Propose settlement"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ConflictDialog({
  entry,
  categories,
  onClose,
  onResolve,
  onWithdraw,
}: {
  entry: SharedEntry;
  categories: { id: string; name: string }[];
  onClose: () => void;
  onResolve: (mode: "absorb" | "remove", categoryId?: string) => Promise<void>;
  onWithdraw: () => Promise<void>;
}) {
  const [categoryId, setCategoryId] = useState(categories[0]?.id ?? "");
  const [busy, setBusy] = useState(false);

  async function run(fn: () => Promise<void>) {
    setBusy(true);
    try {
      await fn();
      onClose();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Resolve rejected share</DialogTitle>
        </DialogHeader>
        <p className="text-sm text-muted-foreground">
          <span className="font-medium text-foreground">{entry.description}</span> was rejected.
          Choose how to reconcile your books — you already paid this amount.
        </p>
        <div className="space-y-1.5">
          <Label>Absorb under category</Label>
          <Select value={categoryId} onValueChange={setCategoryId}>
            <SelectTrigger>
              <SelectValue placeholder="Category" />
            </SelectTrigger>
            <SelectContent>
              {categories.map((c) => (
                <SelectItem key={c.id} value={c.id}>
                  {c.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <DialogFooter className="flex-col gap-2 sm:flex-col">
          <Button
            className="w-full"
            disabled={busy}
            onClick={() => void run(() => onResolve("absorb", categoryId))}
          >
            Absorb as my expense
          </Button>
          <Button
            variant="outline"
            className="w-full"
            disabled={busy}
            onClick={() => void run(() => onResolve("remove"))}
          >
            Remove the claim (it wasn't my cost)
          </Button>
          <Button
            variant="ghost"
            className="w-full text-destructive"
            disabled={busy}
            onClick={() => void run(onWithdraw)}
          >
            Withdraw entry entirely
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
