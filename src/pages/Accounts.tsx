// Accounts (§6.6). CRUD; derived balance; credit-card shows outstanding.

import { useState } from "react";
import { Plus, Pencil, Trash2 } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { createAccount, deleteAccount, updateAccount } from "@/data/mutations";
import type { Account, AccountType } from "@/types/models";
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
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { EmptyState, ErrorState, LoadingState } from "@/components/states";
import { useToast } from "@/components/ui/toast";
import { cn, formatMoney } from "@/lib/utils";

const TYPE_LABELS: Record<AccountType, string> = {
  cash: "Cash",
  bank: "Bank",
  credit_card: "Credit Card",
};

export function Accounts() {
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { accounts, balanceOf, loading, error } = useData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const manage = can("accounts.manage");

  const [editing, setEditing] = useState<Account | "new" | null>(null);
  const [toDelete, setToDelete] = useState<Account | null>(null);

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  return (
    <div>
      <PageHeader
        title="Accounts"
        description="Cash, bank and credit-card accounts. Balances are derived from transactions."
        actions={
          manage && (
            <Button onClick={() => setEditing("new")}>
              <Plus /> New account
            </Button>
          )
        }
      />

      {accounts.length === 0 ? (
        <EmptyState
          title="No accounts yet"
          hint="Add your first cash, bank or credit-card account."
          action={
            manage && <Button onClick={() => setEditing("new")}>New account</Button>
          }
        />
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Type</TableHead>
              <TableHead className="text-right">Opening</TableHead>
              <TableHead className="text-right">Balance</TableHead>
              {manage && <TableHead className="w-24" />}
            </TableRow>
          </TableHeader>
          <TableBody>
            {accounts.map((a) => {
              const bal = balanceOf(a.id);
              const isCard = a.type === "credit_card";
              return (
                <TableRow key={a.id}>
                  <TableCell className="font-medium">{a.name}</TableCell>
                  <TableCell>
                    <Badge variant="secondary">{TYPE_LABELS[a.type]}</Badge>
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {formatMoney(a.openingBalance, currency)}
                  </TableCell>
                  <TableCell
                    className={cn(
                      "text-right tabular-nums font-medium",
                      bal < 0 ? "text-destructive" : "",
                    )}
                  >
                    {isCard && bal < 0
                      ? `${formatMoney(-bal, currency)} owed`
                      : formatMoney(bal, currency)}
                  </TableCell>
                  {manage && (
                    <TableCell>
                      <div className="flex justify-end gap-1">
                        <Button size="icon" variant="ghost" onClick={() => setEditing(a)}>
                          <Pencil />
                        </Button>
                        <Button size="icon" variant="ghost" onClick={() => setToDelete(a)}>
                          <Trash2 />
                        </Button>
                      </div>
                    </TableCell>
                  )}
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      )}

      {editing && activeWorkspaceId && (
        <AccountDialog
          workspaceId={activeWorkspaceId}
          account={editing === "new" ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={() =>
            toast({ title: "Account saved", variant: "success" })
          }
        />
      )}

      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title={`Delete "${toDelete?.name}"?`}
        description="Transactions referencing this account will keep their reference but the account will no longer appear in pickers."
        destructive
        confirmLabel="Delete"
        onConfirm={async () => {
          if (toDelete) {
            await deleteAccount(toDelete.id);
            toast({ title: "Account deleted", variant: "success" });
          }
        }}
      />
    </div>
  );
}

function AccountDialog({
  workspaceId,
  account,
  onClose,
  onSaved,
}: {
  workspaceId: string;
  account: Account | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(account?.name ?? "");
  const [type, setType] = useState<AccountType>(account?.type ?? "bank");
  const [opening, setOpening] = useState(String(account?.openingBalance ?? 0));
  const [busy, setBusy] = useState(false);

  async function save() {
    if (!name.trim()) return;
    setBusy(true);
    try {
      const data = { name: name.trim(), type, openingBalance: Number(opening) || 0 };
      if (account) await updateAccount(account.id, data);
      else await createAccount(workspaceId, data);
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
          <DialogTitle>{account ? "Edit account" : "New account"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="acct-name">Name</Label>
            <Input
              id="acct-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="HDFC Savings"
            />
          </div>
          <div className="space-y-1.5">
            <Label>Type</Label>
            <Select value={type} onValueChange={(v) => setType(v as AccountType)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="cash">Cash</SelectItem>
                <SelectItem value="bank">Bank</SelectItem>
                <SelectItem value="credit_card">Credit Card</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="acct-opening">Opening balance</Label>
            <Input
              id="acct-opening"
              type="number"
              value={opening}
              onChange={(e) => setOpening(e.target.value)}
            />
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
