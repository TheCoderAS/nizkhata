// Transactions (§6.3). List with filters (date, account, category, contact,
// type, has-split) + search + the multi-line entry form.

import { useMemo, useState } from "react";
import { Plus, Pencil, Trash2 } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import {
  createTransaction,
  deleteTransaction,
  updateTransaction,
  type TransactionInput,
} from "@/data/mutations";
import type { LineType, Transaction } from "@/types/models";
import { PageHeader } from "@/components/PageHeader";
import { TransactionFormDialog } from "@/components/TransactionForm";
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
  const [toDelete, setToDelete] = useState<Transaction | null>(null);

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

  const pageItems = filtered.slice(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE);
  const pageCount = Math.ceil(filtered.length / PAGE_SIZE);

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

  return (
    <div>
      <PageHeader
        title="Transactions"
        description="Multi-line entries. Each line carries its own type, category/debt and tax."
        actions={
          create && (
            <Button onClick={() => setFormOpen(true)}>
              <Plus /> New transaction
            </Button>
          )
        }
      />

      {/* filters */}
      <div className="mb-4 flex flex-wrap gap-2">
        <Input
          placeholder="Search note / contact…"
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setPage(0);
          }}
          className="max-w-xs"
        />
        <FilterSelect
          value={accountFilter}
          onChange={setAccountFilter}
          allLabel="All accounts"
          options={accounts.map((a) => ({ value: a.id, label: a.name }))}
        />
        <FilterSelect
          value={contactFilter}
          onChange={setContactFilter}
          allLabel="All contacts"
          options={contacts.map((c) => ({ value: c.id, label: c.name }))}
        />
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
        <Button
          variant={splitOnly ? "default" : "outline"}
          onClick={() => setSplitOnly((s) => !s)}
        >
          Split only
        </Button>
      </div>

      {filtered.length === 0 ? (
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
                <TableHead>Date</TableHead>
                <TableHead>Account</TableHead>
                <TableHead>Contact</TableHead>
                <TableHead>Lines</TableHead>
                <TableHead>Note</TableHead>
                <TableHead className="text-right">Amount</TableHead>
                {(edit || del) && <TableHead className="w-24" />}
              </TableRow>
            </TableHeader>
            <TableBody>
              {pageItems.map((t) => (
                <TableRow key={t.id}>
                  <TableCell className="whitespace-nowrap">{formatDate(toDate(t.date))}</TableCell>
                  <TableCell>{accountsById[t.accountId]?.name ?? "—"}</TableCell>
                  <TableCell>{t.contactId ? contactsById[t.contactId]?.name ?? "—" : "—"}</TableCell>
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
                  <TableCell className="max-w-[160px] truncate text-muted-foreground">
                    {t.note ?? "—"}
                  </TableCell>
                  <TableCell
                    className={cn(
                      "text-right tabular-nums font-medium",
                      t.totalAmount < 0 && "text-destructive",
                      t.totalAmount > 0 && "text-green-600",
                    )}
                  >
                    {formatMoney(t.totalAmount, currency)}
                  </TableCell>
                  {(edit || del) && (
                    <TableCell>
                      <div className="flex justify-end gap-1">
                        {edit && (
                          <Button size="icon" variant="ghost" onClick={() => setEditTxn(t)}>
                            <Pencil />
                          </Button>
                        )}
                        {del && (
                          <Button size="icon" variant="ghost" onClick={() => setToDelete(t)}>
                            <Trash2 />
                          </Button>
                        )}
                      </div>
                    </TableCell>
                  )}
                </TableRow>
              ))}
            </TableBody>
          </Table>

          {pageCount > 1 && (
            <div className="mt-4 flex items-center justify-between text-sm">
              <span className="text-muted-foreground">
                {filtered.length} transactions · page {page + 1} of {pageCount}
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
            toast({ title: "Transaction deleted", variant: "success" });
          }
        }}
      />
    </div>
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
