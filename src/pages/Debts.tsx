// Debts (§6.8). Obligations grouped by direction & purpose; create; settle via a
// repayment transaction (opens the multi-line form pre-seeded with a repayment
// line for the debt).

import { useState } from "react";
import { Plus, HandCoins } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import {
  createDebt,
  createTransaction,
  updateDebt,
  type TransactionInput,
} from "@/data/mutations";
import type { Debt, DebtDirection, DebtPurpose } from "@/types/models";
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
import { formatMoney } from "@/lib/utils";

const PURPOSE_LABELS: Record<DebtPurpose, string> = {
  loan: "Loan",
  custodial_savings: "Custodial savings",
  lending: "Lending",
  reimbursable: "Reimbursable",
  informal: "Informal",
};

export function Debts() {
  const { firebaseUser } = useAuth();
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { debts, contactsById, outstandingOf, loading, error } = useData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const manage = can("debts.manage");
  const canTxn = can("transactions.create");

  const [creating, setCreating] = useState(false);
  const [settling, setSettling] = useState<Debt | null>(null);

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  const owed = debts.filter((d) => d.direction === "owed");
  const owe = debts.filter((d) => d.direction === "owe");

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
        description="Loans, lendings and custodial savings. Outstanding is derived from transactions."
        actions={
          manage && (
            <Button onClick={() => setCreating(true)}>
              <Plus /> New debt
            </Button>
          )
        }
      />

      {debts.length === 0 ? (
        <EmptyState
          title="No debts yet"
          hint="Track money you owe or money owed to you."
          action={manage && <Button onClick={() => setCreating(true)}>New debt</Button>}
        />
      ) : (
        <div className="space-y-8">
          <DebtGroup
            title="They owe you"
            debts={owed}
            currency={currency}
            contactName={(id) => contactsById[id]?.name ?? "—"}
            outstandingOf={outstandingOf}
            onSettle={canTxn ? setSettling : undefined}
            settleLabel="Record receipt"
          />
          <DebtGroup
            title="You owe"
            debts={owe}
            currency={currency}
            contactName={(id) => contactsById[id]?.name ?? "—"}
            outstandingOf={outstandingOf}
            onSettle={canTxn ? setSettling : undefined}
            settleLabel="Record repayment"
          />
        </div>
      )}

      {creating && activeWorkspaceId && (
        <DebtDialog
          workspaceId={activeWorkspaceId}
          onClose={() => setCreating(false)}
          onSaved={() => toast({ title: "Debt created", variant: "success" })}
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
    </div>
  );
}

function DebtGroup({
  title,
  debts,
  currency,
  contactName,
  outstandingOf,
  onSettle,
  settleLabel,
}: {
  title: string;
  debts: Debt[];
  currency: string;
  contactName: (id: string) => string;
  outstandingOf: (id: string) => number;
  onSettle?: (d: Debt) => void;
  settleLabel: string;
}) {
  if (debts.length === 0) return null;
  return (
    <div>
      <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
        {title}
      </h2>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Label</TableHead>
            <TableHead>Contact</TableHead>
            <TableHead>Purpose</TableHead>
            <TableHead>Status</TableHead>
            <TableHead className="text-right">Outstanding</TableHead>
            {onSettle && <TableHead className="w-40" />}
          </TableRow>
        </TableHeader>
        <TableBody>
          {debts.map((d) => {
            const outstanding = outstandingOf(d.id);
            return (
              <TableRow key={d.id}>
                <TableCell className="font-medium">{d.label ?? "—"}</TableCell>
                <TableCell>{contactName(d.contactId)}</TableCell>
                <TableCell>
                  <Badge variant="secondary">{PURPOSE_LABELS[d.purpose]}</Badge>
                </TableCell>
                <TableCell>
                  <Badge variant={d.status === "open" ? "warning" : "success"}>
                    {d.status}
                  </Badge>
                </TableCell>
                <TableCell className="text-right tabular-nums">
                  {formatMoney(outstanding, currency)}
                </TableCell>
                {onSettle && (
                  <TableCell className="text-right">
                    {d.status === "open" && outstanding > 0 && (
                      <Button size="sm" variant="outline" onClick={() => onSettle(d)}>
                        <HandCoins /> {settleLabel}
                      </Button>
                    )}
                  </TableCell>
                )}
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </div>
  );
}

function DebtDialog({
  workspaceId,
  onClose,
  onSaved,
}: {
  workspaceId: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { contacts } = useData();
  const [contactId, setContactId] = useState("");
  const [direction, setDirection] = useState<DebtDirection>("owe");
  const [purpose, setPurpose] = useState<DebtPurpose>("loan");
  const [label, setLabel] = useState("");
  const [principal, setPrincipal] = useState("0");
  const [busy, setBusy] = useState(false);

  async function save() {
    if (!contactId) return;
    setBusy(true);
    try {
      await createDebt(workspaceId, {
        contactId,
        direction,
        purpose,
        principal: Number(principal) || 0,
        label: label.trim() || undefined,
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
          <DialogTitle>New debt</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label>Contact</Label>
            <Select value={contactId} onValueChange={setContactId}>
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
              <Select value={direction} onValueChange={(v) => setDirection(v as DebtDirection)}>
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
              <Select value={purpose} onValueChange={(v) => setPurpose(v as DebtPurpose)}>
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
          <div className="space-y-1.5">
            <Label>Principal (reference)</Label>
            <Input
              type="number"
              value={principal}
              onChange={(e) => setPrincipal(e.target.value)}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !contactId}>
            {busy ? "Saving…" : "Create debt"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
