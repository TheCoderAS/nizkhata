// Shared — Splitwise-style sharing between real app users, ACROSS workspaces.
//
// A shared item is a cross-user proposal: I record my side immediately (I
// already paid), and the counterparty gets a to-do to accept (records a
// balance-only "I owe you") or reject (raises a conflict I resolve). Settlements
// work the same way and require the counterparty's acceptance. Balances are
// derived from accepted entries (+ my own pending expense claims). Partners are
// NOT workspace members and cannot see or enter my workspace.

import { useMemo, useState } from "react";
import {
  Plus,
  Check,
  X,
  Inbox,
  UserPlus,
  AlertTriangle,
  ArrowDownLeft,
  ArrowUpRight,
  Scale,
  Users,
  type LucideIcon,
} from "lucide-react";
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
  rebillSharedEntry,
  rejectSharedEntry,
  resolveConflict,
  withdrawSharedEntry,
  type SharedExpenseParticipant,
} from "@/data/sharedMutations";
import { sharedBalances, toDate } from "@/lib/derive";
import { roundMoney } from "@/lib/txn";
import { cn, formatDate, formatMoney } from "@/lib/utils";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
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
import { EmptyState, ErrorState, PageSkeleton } from "@/components/states";
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
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { firebaseUser } = useAuth();
  const { accounts, categories, contacts, debts, transactions, loading: wsLoading } = useData();
  const { connections, entries, sentInvites, loading: sharedLoading, error } = useSharedData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const fyStartMonth = activeWorkspace?.fyStartMonth ?? 4;
  const myUid = firebaseUser?.uid ?? "";
  // Reading the shared ledger needs only `shared.view` (the route gate);
  // creating/responding/settling needs `shared.manage`.
  const canManage = can("shared.manage");

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

  if (wsLoading || sharedLoading) return <PageSkeleton />;
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

  const owedToMe = balances.filter((b) => b.net > 0).reduce((sum, b) => sum + b.net, 0);
  const iOweTotal = balances.filter((b) => b.net < 0).reduce((sum, b) => sum - b.net, 0);
  const netTotal = owedToMe - iOweTotal;

  return (
    <div className="space-y-5">
      <PageHeader
        title="Shared"
        actions={
          canManage ? (
            <Button variant="outline" size="sm" onClick={() => setInvite(true)}>
              <UserPlus className="h-4 w-4" />
              <span className="hidden sm:inline">Invite</span>
            </Button>
          ) : undefined
        }
        primaryAction={{
          label: "Add expense",
          icon: Plus,
          onClick: () => setAdding(true),
          hidden: partners.length === 0 || !canManage,
        }}
      />

      {/* Summary hero */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <SummaryStat
          label="You are owed"
          value={formatMoney(owedToMe, currency)}
          tone="pos"
          icon={ArrowDownLeft}
        />
        <SummaryStat
          label="You owe"
          value={formatMoney(iOweTotal, currency)}
          tone="neg"
          icon={ArrowUpRight}
        />
        <SummaryStat
          label="Net balance"
          value={`${netTotal < 0 ? "\u2212" : ""}${formatMoney(Math.abs(netTotal), currency)}`}
          tone={netTotal > 0.005 ? "pos" : netTotal < -0.005 ? "neg" : "neutral"}
          icon={Scale}
        />
      </div>

      {/* Inbox */}
      {canManage && inbox.length > 0 && (
        <section className="rounded-xl border border-primary/30 bg-primary/5 p-3 sm:p-4">
          <h2 className="mb-3 flex items-center gap-2 text-sm font-semibold">
            <Inbox className="h-4 w-4 text-primary" /> To review
            <span className="ml-0.5 flex h-5 min-w-5 items-center justify-center rounded-full bg-primary px-1.5 text-[11px] font-semibold text-primary-foreground">
              {inbox.length}
            </span>
          </h2>
          <div className="space-y-2">
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
          </div>
        </section>
      )}

      {/* Conflicts */}
      {canManage && conflicts.length > 0 && (
        <section className="rounded-xl border border-destructive/40 bg-destructive/5 p-3 sm:p-4">
          <h2 className="mb-3 flex items-center gap-2 text-sm font-semibold text-destructive">
            <AlertTriangle className="h-4 w-4" /> Rejected \u2014 needs resolution
          </h2>
          <div className="space-y-1.5">
            {conflicts.map((e) => (
              <div
                key={e.id}
                className="flex items-center justify-between gap-2 rounded-lg bg-card px-3 py-2 text-sm"
              >
                <span className="min-w-0 truncate">
                  <span className="font-medium">{partnerName(e.counterpartyUid)}</span> rejected{" "}
                  <span className="font-medium">{e.description}</span> ·{" "}
                  {formatMoney(e.amount, currency)}
                </span>
                <Button
                  size="sm"
                  variant="outline"
                  className="h-8 shrink-0"
                  onClick={() => setConflict(e)}
                >
                  Resolve
                </Button>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* Partners */}
      <section>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="flex items-center gap-2 text-sm font-semibold">
            <Users className="h-4 w-4 text-muted-foreground" /> Partners
          </h2>
          {pendingInvites.length > 0 && (
            <span className="text-xs text-muted-foreground">
              {pendingInvites.length} pending invite{pendingInvites.length > 1 ? "s" : ""}
            </span>
          )}
        </div>
        {partners.length === 0 ? (
          <div className="rounded-xl border border-dashed p-6 text-center">
            <p className="text-sm font-medium">No partners yet</p>
            <p className="mt-1 text-xs text-muted-foreground">
              Invite someone by email to start splitting expenses.
            </p>
            {canManage && (
              <Button size="sm" className="mt-3" onClick={() => setInvite(true)}>
                <UserPlus className="h-4 w-4" /> Invite a partner
              </Button>
            )}
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {partners.map((p) => {
              const bal = balances.find((b) => b.uid === p.uid);
              const net = bal?.net ?? 0;
              return (
                <PartnerCard
                  key={p.uid}
                  name={p.name}
                  net={net}
                  currency={currency}
                  canSettle={canManage && net < -0.005}
                  onSettle={() => setSettle({ partner: p, amount: Math.abs(net) })}
                />
              );
            })}
          </div>
        )}
      </section>

      {/* History */}
      <section>
        <h2 className="mb-3 text-sm font-semibold">History</h2>
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
          <div className="overflow-hidden rounded-xl border">
            <Table>
              <TableHeader>
                <TableRow className="bg-muted/40">
                  <TableHead>Item</TableHead>
                  <TableHead className="hidden sm:table-cell">With</TableHead>
                  <TableHead className="hidden sm:table-cell">Date</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Amount</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {entries.map((e) => {
                  const other = e.creatorUid === myUid ? e.counterpartyUid : e.creatorUid;
                  const iPaid = e.payerUid === myUid;
                  return (
                    <TableRow key={e.id}>
                      <TableCell>
                        <div className="flex items-center gap-3">
                          <Avatar name={partnerName(other)} />
                          <div className="min-w-0">
                            <div className="flex items-center gap-2">
                              <span className="truncate font-medium">{e.description}</span>
                              {e.kind === "settlement" && (
                                <Badge variant="secondary" className="shrink-0">
                                  settlement
                                </Badge>
                              )}
                            </div>
                            <div className="text-xs text-muted-foreground sm:hidden">
                              {partnerName(other)} · {formatDate(toDate(e.date))}
                            </div>
                          </div>
                        </div>
                      </TableCell>
                      <TableCell className="hidden text-muted-foreground sm:table-cell">
                        {partnerName(other)}
                      </TableCell>
                      <TableCell className="hidden text-muted-foreground sm:table-cell">
                        {formatDate(toDate(e.date))}
                      </TableCell>
                      <TableCell>
                        <StatusBadge entry={e} myUid={myUid} />
                      </TableCell>
                      <TableCell
                        className={cn(
                          "text-right tabular-nums font-medium",
                          iPaid
                            ? "text-emerald-600 dark:text-emerald-400"
                            : "text-destructive",
                        )}
                      >
                        {iPaid ? "+" : "\u2212"}
                        {formatMoney(e.amount, currency)}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        )}
      </section>

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
          onRebill={async () => {
            const refl = transactions.find((t) => t.sharedEntryId === conflict.id);
            await rebillSharedEntry({
              entry: conflict,
              me: firebaseUser!,
              reflectionTxnId: refl?.id ?? null,
            });
            toast({ title: "Re-sent for approval", variant: "success" });
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
  onRebill,
}: {
  entry: SharedEntry;
  categories: { id: string; name: string }[];
  onClose: () => void;
  onResolve: (mode: "absorb" | "remove", categoryId?: string) => Promise<void>;
  onWithdraw: () => Promise<void>;
  onRebill: () => Promise<void>;
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
          <Button className="w-full" disabled={busy} onClick={() => void run(onRebill)}>
            Re-send for approval
          </Button>
          <Button
            variant="outline"
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


function SummaryStat({
  label,
  value,
  tone,
  icon: Icon,
}: {
  label: string;
  value: string;
  tone: "pos" | "neg" | "neutral";
  icon: LucideIcon;
}) {
  return (
    <div className="rounded-xl border bg-card p-4">
      <div className="flex items-center justify-between text-xs text-muted-foreground">
        <span>{label}</span>
        <Icon
          className={cn(
            "h-4 w-4",
            tone === "pos" && "text-emerald-600 dark:text-emerald-400",
            tone === "neg" && "text-destructive",
          )}
        />
      </div>
      <div
        className={cn(
          "mt-1 truncate font-strong text-xl tabular-nums sm:text-2xl",
          tone === "pos" && "text-emerald-600 dark:text-emerald-400",
          tone === "neg" && "text-destructive",
        )}
      >
        {value}
      </div>
    </div>
  );
}

function PartnerCard({
  name,
  net,
  currency,
  canSettle,
  onSettle,
}: {
  name: string;
  net: number;
  currency: string;
  canSettle: boolean;
  onSettle: () => void;
}) {
  const settled = Math.abs(net) < 0.005;
  const owesMe = net > 0;
  return (
    <div className="flex items-center gap-3 rounded-xl border bg-card p-3">
      <Avatar name={name} />
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium">{name}</p>
        <p
          className={cn(
            "truncate text-xs",
            settled
              ? "text-muted-foreground"
              : owesMe
                ? "text-emerald-600 dark:text-emerald-400"
                : "text-destructive",
          )}
        >
          {settled
            ? "Settled up"
            : owesMe
              ? `owes you ${formatMoney(net, currency)}`
              : `you owe ${formatMoney(-net, currency)}`}
        </p>
      </div>
      {canSettle && (
        <Button size="sm" variant="outline" className="h-8 shrink-0" onClick={onSettle}>
          Settle
        </Button>
      )}
    </div>
  );
}

function Avatar({ name }: { name: string }) {
  const initials =
    name
      .trim()
      .split(/\s+/)
      .slice(0, 2)
      .map((w) => w[0]?.toUpperCase() ?? "")
      .join("") || "?";
  return (
    <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary">
      {initials}
    </span>
  );
}
