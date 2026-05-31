// Transactions (§6.3). List with filters (date, account, category, contact,
// type, has-split) + search + pagination + sortable headers. Rows open a detail
// modal; row actions live in a kebab menu (both on the row and in the modal).

import { useMemo, useState } from "react";
import { Plus, Pencil, Trash2, Eye } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import {
  EXTERNAL_ACCOUNT,
  createTransaction,
  deleteTransaction,
  updateTransaction,
  type TransactionInput,
} from "@/data/mutations";
import type { LineType, Transaction } from "@/types/models";
import { PageHeader } from "@/components/PageHeader";
import { TransactionFormDialog } from "@/components/TransactionForm";
import { RowActions, type RowAction } from "@/components/RowActions";
import { SortableHead } from "@/components/SortableHead";
import { DetailDialog, type DetailField } from "@/components/DetailDialog";
import { FilterModal, FilterRow } from "@/components/FilterModal";
import { ColumnsMenu } from "@/components/ColumnsMenu";
import { useColumnPrefs, type ColumnDef } from "@/lib/useColumnPrefs";
import { useSort, type SortAccessor } from "@/lib/useSort";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
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
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { EmptyState, ErrorState, LoadingState } from "@/components/states";
import { useToast } from "@/components/ui/toast";
import { toDate } from "@/lib/derive";
import { cn, formatDate, formatMoney } from "@/lib/utils";

const PAGE_SIZE = 25;

type SortKey = "date" | "account" | "contact" | "amount";
type ColKey = "date" | "account" | "contact" | "lines" | "note" | "amount";

// Minimal default view (4 columns); the rest are opt-in via the columns menu.
const COLUMNS: ColumnDef<ColKey>[] = [
  { key: "date", label: "Date", defaultVisible: true },
  { key: "account", label: "Account", defaultVisible: true },
  { key: "contact", label: "Contact", defaultVisible: false },
  { key: "lines", label: "Lines", defaultVisible: false },
  { key: "note", label: "Note", defaultVisible: false },
  { key: "amount", label: "Amount", defaultVisible: true },
];

export function Transactions() {
  const { firebaseUser } = useAuth();
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { transactions, accounts, contacts, accountsById, contactsById, loading, error } =
    useData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";

  const create = can("transactions.create");
  const edit = can("transactions.edit");
  const del = can("transactions.delete");

  const [search, setSearch] = useState("");
  const [accountFilter, setAccountFilter] = useState("__all");
  const [contactFilter, setContactFilter] = useState("__all");
  const [typeFilter, setTypeFilter] = useState("__all");
  const [splitOnly, setSplitOnly] = useState(false);
  const [page, setPage] = useState(0);

  const [formOpen, setFormOpen] = useState(false);
  const [editTxn, setEditTxn] = useState<Transaction | null>(null);
  const [viewTxn, setViewTxn] = useState<Transaction | null>(null);
  const [toDelete, setToDelete] = useState<Transaction | null>(null);

  const cols = useColumnPrefs<ColKey>("transactions", COLUMNS);

  const activeFilterCount =
    (accountFilter !== "__all" ? 1 : 0) +
    (contactFilter !== "__all" ? 1 : 0) +
    (typeFilter !== "__all" ? 1 : 0) +
    (splitOnly ? 1 : 0);
  function clearFilters() {
    setAccountFilter("__all");
    setContactFilter("__all");
    setTypeFilter("__all");
    setSplitOnly(false);
    setPage(0);
  }

  const filtered = useMemo(() => {
    return transactions.filter((t) => {
      if (accountFilter !== "__all" && t.accountId !== accountFilter) return false;
      if (contactFilter !== "__all" && t.contactId !== contactFilter) return false;
      if (splitOnly && !t.hasSplit) return false;
      if (typeFilter !== "__all" && !t.lines.some((l) => l.type === typeFilter)) return false;
      if (search) {
        const hay = `${t.note ?? ""} ${contactsById[t.contactId ?? ""]?.name ?? ""}`.toLowerCase();
        if (!hay.includes(search.toLowerCase())) return false;
      }
      return true;
    });
  }, [transactions, accountFilter, contactFilter, splitOnly, typeFilter, search, contactsById]);

  const accessors: Record<SortKey, SortAccessor<Transaction>> = useMemo(
    () => ({
      date: (t) => toDate(t.date),
      account: (t) => accountsById[t.accountId]?.name ?? "",
      contact: (t) => (t.contactId ? contactsById[t.contactId]?.name ?? "" : ""),
      amount: (t) => t.totalAmount,
    }),
    [accountsById, contactsById],
  );
  const { sorted, sort, toggle } = useSort(filtered, accessors, {
    key: "date",
    direction: "desc",
  });

  const pageItems = sorted.slice(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE);
  const pageCount = Math.ceil(sorted.length / PAGE_SIZE);

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  async function handleCreate(input: TransactionInput) {
    if (!activeWorkspaceId || !firebaseUser) return;
    await createTransaction(activeWorkspaceId, firebaseUser.uid, input);
    toast({ title: "Transaction added", variant: "success" });
  }
  async function handleUpdate(input: TransactionInput) {
    if (!activeWorkspaceId || !editTxn) return;
    await updateTransaction(editTxn.id, activeWorkspaceId, editTxn.createdBy, input);
    toast({ title: "Transaction updated", variant: "success" });
  }

  function rowActions(t: Transaction): RowAction[] {
    return [
      { label: "View details", icon: Eye, onSelect: () => setViewTxn(t) },
      { label: "Edit", icon: Pencil, onSelect: () => setEditTxn(t), hidden: !edit },
      {
        label: "Delete",
        icon: Trash2,
        onSelect: () => setToDelete(t),
        destructive: true,
        separatorBefore: true,
        hidden: !del,
      },
    ];
  }

  return (
    <div>
      <PageHeader
        title="Transactions"
        primaryAction={{
          label: "New transaction",
          icon: Plus,
          onClick: () => setFormOpen(true),
          hidden: !create,
        }}
      />

      {/* toolbar: search + filters modal + column chooser */}
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Input
          placeholder="Search note / contact…"
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setPage(0);
          }}
          className="max-w-xs"
        />
        <FilterModal activeCount={activeFilterCount} onClear={clearFilters}>
          <FilterRow label="Account">
            <FilterSelect
              value={accountFilter}
              onChange={setAccountFilter}
              allLabel="All accounts"
              options={accounts.map((a) => ({ value: a.id, label: a.name }))}
            />
          </FilterRow>
          <FilterRow label="Contact">
            <FilterSelect
              value={contactFilter}
              onChange={setContactFilter}
              allLabel="All contacts"
              options={contacts.map((c) => ({ value: c.id, label: c.name }))}
            />
          </FilterRow>
          <FilterRow label="Line type">
            <FilterSelect
              value={typeFilter}
              onChange={setTypeFilter}
              allLabel="All types"
              options={(
                [
                  "income",
                  "expense",
                  "transfer_out",
                  "transfer_in",
                  "borrow",
                  "lend",
                  "repayment",
                  "fee",
                  "interest_income",
                  "interest_expense",
                  "tax",
                ] as LineType[]
              ).map((t) => ({ value: t, label: t }))}
            />
          </FilterRow>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={splitOnly}
              onChange={(e) => setSplitOnly(e.target.checked)}
            />
            Split transactions only
          </label>
        </FilterModal>
        <div className="ml-auto">
          <ColumnsMenu columns={cols.columns} isVisible={cols.isVisible} toggle={cols.toggle} reset={cols.reset} />
        </div>
      </div>

      {sorted.length === 0 ? (
        <EmptyState
          title="No transactions"
          hint={transactions.length > 0 ? "Try clearing filters." : "Record your first transaction."}
          action={create && transactions.length === 0 && (
            <Button onClick={() => setFormOpen(true)}>New transaction</Button>
          )}
        />
      ) : (
        <>
          <Table>
            <TableHeader>
              <TableRow>
                {cols.isVisible("date") && (
                  <SortableHead sortKey="date" sort={sort} onToggle={toggle}>
                    Date
                  </SortableHead>
                )}
                {cols.isVisible("account") && (
                  <SortableHead sortKey="account" sort={sort} onToggle={toggle}>
                    Account
                  </SortableHead>
                )}
                {cols.isVisible("contact") && (
                  <SortableHead sortKey="contact" sort={sort} onToggle={toggle}>
                    Contact
                  </SortableHead>
                )}
                {cols.isVisible("lines") && <TableHead>Lines</TableHead>}
                {cols.isVisible("note") && <TableHead>Note</TableHead>}
                {cols.isVisible("amount") && (
                  <SortableHead sortKey="amount" sort={sort} onToggle={toggle} className="text-right">
                    Amount
                  </SortableHead>
                )}
                <TableHead className="w-12" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {pageItems.map((t) => (
                <TableRow
                  key={t.id}
                  onClick={() => setViewTxn(t)}
                  className="cursor-pointer"
                >
                  {cols.isVisible("date") && (
                    <TableCell className="whitespace-nowrap">{formatDate(toDate(t.date))}</TableCell>
                  )}
                  {cols.isVisible("account") && (
                    <TableCell>
                      {accountsById[t.accountId]?.name ??
                        (t.accountId === EXTERNAL_ACCOUNT ? "External" : "—")}
                    </TableCell>
                  )}
                  {cols.isVisible("contact") && (
                    <TableCell>{t.contactId ? contactsById[t.contactId]?.name ?? "—" : "—"}</TableCell>
                  )}
                  {cols.isVisible("lines") && (
                    <TableCell>
                      <div className="flex flex-wrap gap-1">
                        {t.lines.slice(0, 3).map((l) => (
                          <Badge key={l.lineId} variant="secondary" className="text-[10px]">
                            {l.type}
                          </Badge>
                        ))}
                        {t.lines.length > 3 && (
                          <Badge variant="outline" className="text-[10px]">
                            +{t.lines.length - 3}
                          </Badge>
                        )}
                      </div>
                    </TableCell>
                  )}
                  {cols.isVisible("note") && (
                    <TableCell className="max-w-[160px] truncate text-muted-foreground">
                      {t.note ?? "—"}
                    </TableCell>
                  )}
                  {cols.isVisible("amount") && (
                    <TableCell
                      className={cn(
                        "text-right tabular-nums font-medium",
                        t.totalAmount < 0 && "text-destructive",
                        t.totalAmount > 0 && "text-green-600",
                      )}
                    >
                      {formatMoney(t.totalAmount, currency)}
                    </TableCell>
                  )}
                  <TableCell>
                    <RowActions actions={rowActions(t)} />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>

          {pageCount > 1 && (
            <div className="mt-4 flex items-center justify-between text-sm">
              <span className="text-muted-foreground">
                {sorted.length} transactions · page {page + 1} of {pageCount}
              </span>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  variant="outline"
                  disabled={page === 0}
                  onClick={() => setPage((p) => p - 1)}
                >
                  Previous
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={page >= pageCount - 1}
                  onClick={() => setPage((p) => p + 1)}
                >
                  Next
                </Button>
              </div>
            </div>
          )}
        </>
      )}

      {viewTxn && (
        <TransactionDetail
          txn={viewTxn}
          currency={currency}
          accountName={(id) => accountsById[id]?.name ?? "—"}
          contactName={(id) => contactsById[id]?.name ?? "—"}
          actions={rowActions(viewTxn).filter((a) => a.label !== "View details")}
          onClose={() => setViewTxn(null)}
        />
      )}

      {formOpen && (
        <TransactionFormDialog
          open
          onClose={() => setFormOpen(false)}
          onSubmit={handleCreate}
          title="New transaction"
        />
      )}
      {editTxn && (
        <TransactionFormDialog
          open
          onClose={() => setEditTxn(null)}
          onSubmit={handleUpdate}
          title="Edit transaction"
          initial={{ txn: editTxn }}
        />
      )}

      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title="Delete transaction?"
        description="This removes the entry and its effect on balances and reports."
        destructive
        confirmLabel="Delete"
        onConfirm={async () => {
          if (toDelete) {
            await deleteTransaction(toDelete.id);
            setViewTxn(null);
            toast({ title: "Transaction deleted", variant: "success" });
          }
        }}
      />
    </div>
  );
}

function TransactionDetail({
  txn,
  currency,
  accountName,
  contactName,
  actions,
  onClose,
}: {
  txn: Transaction;
  currency: string;
  accountName: (id: string) => string;
  contactName: (id: string) => string;
  actions: RowAction[];
  onClose: () => void;
}) {
  const fields: DetailField[] = [
    { label: "Date", value: formatDate(toDate(txn.date)) },
    { label: "Account", value: accountName(txn.accountId) },
    {
      label: "Contact",
      value: txn.contactId ? contactName(txn.contactId) : "—",
    },
    { label: "Financial year", value: txn.financialYear },
    {
      label: "Total",
      value: (
        <span
          className={cn(
            "tabular-nums",
            txn.totalAmount < 0 && "text-destructive",
            txn.totalAmount > 0 && "text-green-600",
          )}
        >
          {formatMoney(txn.totalAmount, currency)}
        </span>
      ),
    },
    { label: "Note", value: txn.note ?? "—", block: true, hidden: !txn.note },
  ];

  return (
    <DetailDialog
      open
      onClose={onClose}
      title="Transaction"
      subtitle={`${txn.lines.length} line${txn.lines.length > 1 ? "s" : ""}`}
      fields={fields}
      actions={actions}
    >
      <div className="mt-2">
        <p className="mb-2 text-sm font-medium">Lines</p>
        <div className="space-y-2">
          {txn.lines.map((l) => (
            <div
              key={l.lineId}
              className="flex items-center justify-between rounded-md border p-2 text-sm"
            >
              <div className="flex items-center gap-2">
                <Badge variant="secondary" className="text-[10px]">
                  {l.type}
                </Badge>
                {l.tax?.taxable && (
                  <Badge variant="outline" className="text-[10px]">
                    tax: {l.tax.head}
                  </Badge>
                )}
                {l.note && <span className="text-muted-foreground">{l.note}</span>}
              </div>
              <span className="tabular-nums">{formatMoney(l.amount, currency)}</span>
            </div>
          ))}
        </div>
      </div>
    </DetailDialog>
  );
}

function FilterSelect({
  value,
  onChange,
  allLabel,
  options,
}: {
  value: string;
  onChange: (v: string) => void;
  allLabel: string;
  options: { value: string; label: string }[];
}) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger className="w-40">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="__all">{allLabel}</SelectItem>
        {options.map((o) => (
          <SelectItem key={o.value} value={o.value}>
            {o.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
