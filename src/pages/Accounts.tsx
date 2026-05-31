// Accounts (§6.6). CRUD; derived balance; credit-card shows outstanding.
// Sortable headers; rows open a detail modal; actions in a kebab menu.

import { useMemo, useState } from "react";
import { Plus, Pencil, Trash2, ScrollText } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { createAccount, deleteAccount, updateAccount } from "@/data/mutations";
import type { Account, AccountType } from "@/types/models";
import { PageHeader } from "@/components/PageHeader";
import { RowActions, type RowAction } from "@/components/RowActions";
import { SortableHead } from "@/components/SortableHead";
import { DetailDialog, type DetailField } from "@/components/DetailDialog";
import { ColumnsMenu } from "@/components/ColumnsMenu";
import { ResizableTable } from "@/components/ResizableTable";
import { useColumnPrefs, type ColumnDef } from "@/lib/useColumnPrefs";
import { useSort, type SortAccessor } from "@/lib/useSort";
import { usePagination } from "@/lib/usePagination";
import { Pagination } from "@/components/Pagination";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
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
import { EmptyState, ErrorState, LoadingState } from "@/components/states";
import { useToast } from "@/components/ui/toast";
import { cn, formatMoney } from "@/lib/utils";

const TYPE_LABELS: Record<AccountType, string> = {
  cash: "Cash",
  bank: "Bank",
  credit_card: "Credit Card",
};

// Optional metadata fields exposed per account type, in display order.
type MetaKey =
  | "code"
  | "accountNumber"
  | "cif"
  | "ifsc"
  | "branchName"
  | "nameOnCard"
  | "cardLast4"
  | "cardExpiry"
  | "description";

const ACCOUNT_FIELDS: Record<AccountType, MetaKey[]> = {
  cash: ["code", "description"],
  bank: ["accountNumber", "ifsc", "cif", "branchName", "code", "description"],
  credit_card: ["nameOnCard", "cardLast4", "cardExpiry", "code", "description"],
};

const FIELD_META: Record<
  MetaKey,
  { label: string; placeholder?: string; numeric?: boolean; maxLength?: number; full?: boolean }
> = {
  code: { label: "Code" },
  accountNumber: { label: "Account number", numeric: true },
  cif: { label: "CIF number", numeric: true },
  ifsc: { label: "IFSC code", placeholder: "ABCD0123456" },
  branchName: { label: "Branch name" },
  nameOnCard: { label: "Name on card" },
  cardLast4: { label: "Card (last 4)", placeholder: "1234", numeric: true, maxLength: 4 },
  cardExpiry: { label: "Expiry", placeholder: "MM/YY", maxLength: 5 },
  description: { label: "Description", full: true },
};

// A short masked identifier for list/detail: "•••• 1234".
function maskedIdentifier(a: Account): string | null {
  if (a.cardLast4) return `•••• ${a.cardLast4}`;
  if (a.accountNumber) return `••••${a.accountNumber.slice(-4)}`;
  return null;
}

// Normalize free typing into MM/YY.
function formatExpiry(raw: string): string {
  const digits = raw.replace(/[^0-9]/g, "").slice(0, 4);
  return digits.length <= 2 ? digits : `${digits.slice(0, 2)}/${digits.slice(2)}`;
}

type SortKey = "name" | "type" | "opening" | "balance";
type ColKey = "name" | "type" | "opening" | "balance";

const COLUMNS: ColumnDef<ColKey>[] = [
  { key: "name", label: "Name", defaultVisible: true, locked: true },
  { key: "type", label: "Type", defaultVisible: true },
  { key: "opening", label: "Opening", defaultVisible: false },
  { key: "balance", label: "Balance", defaultVisible: true },
];

export function Accounts() {
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { accounts, balanceOf, loading, error } = useData();
  const { toast } = useToast();
  const navigate = useNavigate();
  const cols = useColumnPrefs<ColKey>("accounts", COLUMNS);
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
  const pagination = usePagination(sorted);
  const { pageItems } = pagination;

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  function rowActions(a: Account): RowAction[] {
    return [
      {
        label: "View ledger",
        icon: ScrollText,
        onSelect: () => navigate(`/settings/accounts/${a.id}/ledger`),
      },
      { label: "Edit", icon: Pencil, onSelect: () => setEditing(a), separatorBefore: true, hidden: !manage },
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
        primaryAction={{
          label: "New account",
          icon: Plus,
          onClick: () => setEditing("new"),
          hidden: !manage,
        }}
      />

      {accounts.length > 0 && (
        <div className="mb-4 flex justify-end">
          <ColumnsMenu columns={cols.columns} isVisible={cols.isVisible} toggle={cols.toggle} reset={cols.reset} hasCustomWidths={cols.hasCustomWidths} onResetWidths={cols.resetWidths} />
        </div>
      )}

      {accounts.length === 0 ? (
        <EmptyState
          title="No accounts yet"
          hint="Add your first cash, bank or credit-card account."
          action={
            manage && <Button onClick={() => setEditing("new")}>New account</Button>
          }
        />
      ) : (
        <ResizableTable prefs={cols} className="[&_td]:truncate">
          <TableHeader>
            <TableRow>
              {cols.isVisible("name") && (
                <SortableHead sortKey="name" sort={sort} onToggle={toggle}>
                  Name
                </SortableHead>
              )}
              {cols.isVisible("type") && (
                <SortableHead sortKey="type" sort={sort} onToggle={toggle}>
                  Type
                </SortableHead>
              )}
              {cols.isVisible("opening") && (
                <SortableHead sortKey="opening" sort={sort} onToggle={toggle} className="text-right">
                  Opening
                </SortableHead>
              )}
              {cols.isVisible("balance") && (
                <SortableHead sortKey="balance" sort={sort} onToggle={toggle} className="text-right">
                  Balance
                </SortableHead>
              )}
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {pageItems.map((a) => {
              const bal = balanceOf(a.id);
              const isCard = a.type === "credit_card";
              return (
                <TableRow
                  key={a.id}
                  onClick={() => setViewing(a)}
                  className="cursor-pointer"
                >
                  {cols.isVisible("name") && (
                    <TableCell>
                      <span className="flex flex-col">
                        <span>{a.name}</span>
                        {maskedIdentifier(a) && (
                          <span className="text-xs tabular-nums text-muted-foreground">
                            {maskedIdentifier(a)}
                          </span>
                        )}
                      </span>
                    </TableCell>
                  )}
                  {cols.isVisible("type") && (
                    <TableCell>
                      <Badge variant="secondary">{TYPE_LABELS[a.type]}</Badge>
                    </TableCell>
                  )}
                  {cols.isVisible("opening") && (
                    <TableCell className="text-right tabular-nums">
                      {formatMoney(a.openingBalance, currency)}
                    </TableCell>
                  )}
                  {cols.isVisible("balance") && (
                    <TableCell
                      className={cn(
                        "font-strong text-right tabular-nums",
                        bal < 0 ? "text-destructive" : "",
                      )}
                    >
                      {isCard && bal < 0
                        ? `${formatMoney(-bal, currency)} owed`
                        : formatMoney(bal, currency)}
                    </TableCell>
                  )}
                  <TableCell>
                    <RowActions actions={rowActions(a)} />
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </ResizableTable>
      )}

      {accounts.length > 0 && <Pagination state={pagination} noun="accounts" />}

      {viewing && (
        <AccountDetail
          account={viewing}
          balance={balanceOf(viewing.id)}
          currency={currency}
          actions={rowActions(viewing)}
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
  // Append any populated metadata fields, in the type's display order.
  for (const key of ACCOUNT_FIELDS[account.type]) {
    const v = account[key as keyof Account];
    if (typeof v === "string" && v.trim()) {
      fields.push({ label: FIELD_META[key].label, value: v });
    }
  }
  return (
    <DetailDialog
      open
      onClose={onClose}
      title={account.name}
      fields={fields}
      actions={actions}
      entityId={account.id}
      audit={{
        createdBy: account.createdBy,
        createdAt: account.createdAt,
        updatedBy: account.updatedBy,
        updatedAt: account.updatedAt,
      }}
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
  const [meta, setMeta] = useState<Record<MetaKey, string>>(() => ({
    code: account?.code ?? "",
    accountNumber: account?.accountNumber ?? "",
    cif: account?.cif ?? "",
    ifsc: account?.ifsc ?? "",
    branchName: account?.branchName ?? "",
    nameOnCard: account?.nameOnCard ?? "",
    cardLast4: account?.cardLast4 ?? "",
    cardExpiry: account?.cardExpiry ?? "",
    description: account?.description ?? "",
  }));
  const [busy, setBusy] = useState(false);

  const fields = ACCOUNT_FIELDS[type];

  function setField(key: MetaKey, raw: string) {
    const m = FIELD_META[key];
    let v = raw;
    if (key === "cardExpiry") v = formatExpiry(raw);
    else if (m.numeric) v = v.replace(/[^0-9]/g, "");
    if (m.maxLength) v = v.slice(0, m.maxLength);
    if (key === "ifsc") v = v.toUpperCase();
    setMeta((prev) => ({ ...prev, [key]: v }));
  }

  async function save() {
    if (!name.trim()) return;
    setBusy(true);
    try {
      // Persist only fields relevant to the chosen type; blanks -> undefined.
      const metaOut: Partial<Record<MetaKey, string | undefined>> = {};
      for (const key of fields) metaOut[key] = meta[key].trim() || undefined;
      const data = {
        name: name.trim(),
        type,
        openingBalance: Number(opening) || 0,
        ...metaOut,
      };
      if (account) await updateAccount(account.id, data);
      else await createAccount(workspaceId, data);
      onSaved();
      onClose();
    } finally {
      setBusy(false);
    }
  }

  const isCard = type === "credit_card";

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] max-w-md overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{account ? "Edit account" : "New account"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
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

          <div className="grid grid-cols-2 gap-3">
            {fields.map((key) => {
              const m = FIELD_META[key];
              return (
                <div key={key} className={m.full ? "col-span-2 space-y-1.5" : "space-y-1.5"}>
                  <Label>{m.label}</Label>
                  {m.full ? (
                    <Textarea
                      rows={2}
                      value={meta[key]}
                      placeholder={m.placeholder}
                      onChange={(e) => setField(key, e.target.value)}
                    />
                  ) : (
                    <Input
                      value={meta[key]}
                      placeholder={m.placeholder}
                      inputMode={m.numeric ? "numeric" : undefined}
                      onChange={(e) => setField(key, e.target.value)}
                    />
                  )}
                </div>
              );
            })}
          </div>

          {isCard && (
            <p className="text-xs text-muted-foreground">
              For your safety we never store the full card number or CVV — only the last 4 digits.
            </p>
          )}
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
