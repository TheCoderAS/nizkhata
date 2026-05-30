// Dues (§6.4). Payable/receivable obligations with status + due date.
// "Record payment" creates a transaction linked via dueId; partial settlement
// keeps the due in "partial" until fully covered.

import { useState } from "react";
import { Plus, Receipt } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import {
  createDue,
  settleDue,
  type TransactionInput,
} from "@/data/mutations";
import type { Due, DueDirection } from "@/types/models";
import { dueStatusFromSettled, toDate } from "@/lib/derive";
import { PageHeader } from "@/components/PageHeader";
import { TransactionFormDialog } from "@/components/TransactionForm";
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
import { EmptyState, ErrorState, LoadingState } from "@/components/states";
import { useToast } from "@/components/ui/toast";
import { formatDate, formatMoney } from "@/lib/utils";

export function Dues() {
  const { firebaseUser } = useAuth();
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { dues, contactsById, settledOf, loading, error } = useData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const manage = can("dues.manage");
  const canTxn = can("transactions.create");

  const [creating, setCreating] = useState(false);
  const [paying, setPaying] = useState<Due | null>(null);

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

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
        description="Pay-later bills and expected receipts. Settle them with a transaction."
        actions={
          manage && (
            <Button onClick={() => setCreating(true)}>
              <Plus /> New due
            </Button>
          )
        }
      />

      {dues.length === 0 ? (
        <EmptyState
          title="No dues"
          hint="Track upcoming bills (payable) or expected income (receivable)."
          action={manage && <Button onClick={() => setCreating(true)}>New due</Button>}
        />
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Title</TableHead>
              <TableHead>Direction</TableHead>
              <TableHead>Contact</TableHead>
              <TableHead>Due date</TableHead>
              <TableHead className="text-right">Amount</TableHead>
              <TableHead className="text-right">Settled</TableHead>
              <TableHead>Status</TableHead>
              {canTxn && <TableHead className="w-32" />}
            </TableRow>
          </TableHeader>
          <TableBody>
            {dues.map((d) => {
              const settled = settledOf(d.id);
              const status = dueStatusFromSettled(d, settled);
              return (
                <TableRow key={d.id}>
                  <TableCell className="font-medium">{d.title}</TableCell>
                  <TableCell>
                    <Badge variant={d.direction === "receivable" ? "success" : "warning"}>
                      {d.direction}
                    </Badge>
                  </TableCell>
                  <TableCell>{d.contactId ? contactsById[d.contactId]?.name ?? "—" : "—"}</TableCell>
                  <TableCell className="whitespace-nowrap">{formatDate(toDate(d.dueDate))}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    {formatMoney(d.amount, currency)}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {formatMoney(settled, currency)}
                  </TableCell>
                  <TableCell>
                    <Badge
                      variant={
                        status === "settled"
                          ? "success"
                          : status === "partial"
                            ? "warning"
                            : status === "cancelled"
                              ? "outline"
                              : "secondary"
                      }
                    >
                      {status}
                    </Badge>
                  </TableCell>
                  {canTxn && (
                    <TableCell className="text-right">
                      {status !== "settled" && status !== "cancelled" && (
                        <Button size="sm" variant="outline" onClick={() => setPaying(d)}>
                          <Receipt /> Record
                        </Button>
                      )}
                    </TableCell>
                  )}
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      )}

      {creating && activeWorkspaceId && (
        <DueDialog
          workspaceId={activeWorkspaceId}
          onClose={() => setCreating(false)}
          onSaved={() => toast({ title: "Due created", variant: "success" })}
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
    </div>
  );
}

function DueDialog({
  workspaceId,
  onClose,
  onSaved,
}: {
  workspaceId: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { contacts, accounts } = useData();
  const [direction, setDirection] = useState<DueDirection>("payable");
  const [title, setTitle] = useState("");
  const [amount, setAmount] = useState("0");
  const [dueDate, setDueDate] = useState(new Date().toISOString().slice(0, 10));
  const [contactId, setContactId] = useState("");
  const [accountId, setAccountId] = useState("");
  const [busy, setBusy] = useState(false);

  async function save() {
    if (!title.trim()) return;
    setBusy(true);
    try {
      const { Timestamp } = await import("firebase/firestore");
      await createDue(workspaceId, {
        direction,
        title: title.trim(),
        amount: Number(amount) || 0,
        dueDate: Timestamp.fromDate(new Date(dueDate)) as never,
        contactId: contactId || undefined,
        accountId: accountId || undefined,
      });
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
          <DialogTitle>New due</DialogTitle>
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
            {busy ? "Saving…" : "Create due"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
