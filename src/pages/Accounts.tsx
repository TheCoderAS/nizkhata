// Accounts (§6.6). CRUD; derived balance; credit-card shows outstanding.
// Sortable headers; rows open a detail modal; actions in a kebab menu.

import { useMemo, useState } from "react";
import { Plus, Pencil, Trash2, Eye } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { createAccount, deleteAccount, updateAccount } from "@/data/mutations";
import type { Account, AccountType } from "@/types/models";
import { PageHeader } from "@/components/PageHeader";
import { RowActions, type RowAction } from "@/components/RowActions";
import { SortableHead } from "@/components/SortableHead";
import { DetailDialog, type DetailField } from "@/components/DetailDialog";
import { useSort, type SortAccessor } from "@/lib/useSort";
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

type SortKey = "name" | "type" | "opening" | "balance";

export function Accounts() {
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { accounts, balanceOf, loading, error } = useData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const manage = can("accounts.manage");

  const [editing, setEditing] = useState<Account | "new" | null>(null);
  const [viewing, setViewing] = useState<Account | null>(null);
  const [toDelete, setToDelete] = useState<Account | null>(null);

  const accessors: Record<SortKey, SortAccessor<Account>> = useMemo(
    () => ({
      name: (a) => a.name,
      type: (a) => TYPE_LABELS[a.type],
      opening: (a) => a.openingBalance,
      balance: (a) => balanceOf(a.id),
    }),
    [balanceOf],
  );
  const { sorted, sort, toggle } = useSort(accounts, accessors, {
    key: "name",
    direction: "asc",
  });

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  function rowActions(a: Account): RowAction[] {
    return [
      { label: "View details", icon: Eye, onSelect: () => setViewing(a) },
      { label: "Edit", icon: Pencil, onSelect: () => setEditing(a), hidden: !manage },
      {
        label: "Delete",
        icon: Trash2,
        onSelect: () => setToDelete(a),
        destructive: true,
        separatorBefore: true,
        hidden: !manage,
      },
    ];
  }

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
              <SortableHead sortKey="name" sort={sort} onToggle={toggle}>
                Name
              </SortableHead>
              <SortableHead sortKey="type" sort={sort} onToggle={toggle}>
                Type
              </SortableHead>
              <SortableHead sortKey="opening" sort={sort} onToggle={toggle} className="text-right">
                Opening
              </SortableHead>
              <SortableHead sortKey="balance" sort={sort} onToggle={toggle} className="text-right">
                Balance
              </SortableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {sorted.map((a) => {
              const bal = balanceOf(a.id);
              const isCard = a.type === "credit_card";
              return (
                <TableRow
                  key={a.id}
                  onClick={() => setViewing(a)}
                  className="cursor-pointer"
                >
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
                  <TableCell>
                    <RowActions actions={rowActions(a)} />
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      )}

      {viewing && (
        <AccountDetail
          account={viewing}
          balance={balanceOf(viewing.id)}
          currency={currency}
          actions={rowActions(viewing).filter((a) => a.label !== "View details")}
          onClose={() => setViewing(null)}
        />
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
            setViewing(null);
            toast({ title: "Account deleted", variant: "success" });
          }
        }}
      />
    </div>
  );
}

function AccountDetail({
  account,
  balance,
  currency,
  actions,
  onClose,
}: {
  account: Account;
  balance: number;
  currency: string;
  actions: RowAction[];
  onClose: () => void;
}) {
  const isCard = account.type === "credit_card";
  const fields: DetailField[] = [
    { label: "Type", value: TYPE_LABELS[account.type] },
    { label: "Opening balance", value: formatMoney(account.openingBalance, currency) },
    {
      label: "Current balance",
      value: (
        <span className={cn("tabular-nums", balance < 0 && "text-destructive")}>
          {isCard && balance < 0
            ? `${formatMoney(-balance, currency)} owed`
            : formatMoney(balance, currency)}
        </span>
      ),
    },
  ];
  return (
    <DetailDialog
      open
      onClose={onClose}
      title={account.name}
      subtitle={TYPE_LABELS[account.type]}
      fields={fields}
      actions={actions}
    />
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
