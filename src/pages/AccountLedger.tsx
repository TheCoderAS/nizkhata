// Account ledger (passbook) — a single account's statement: every transaction
// that moves this account, oldest→newest, with a running balance per row that
// starts from the account's opening balance and ends at its current balance.
// Reachable from the account detail dialog ("View ledger").

import { useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ArrowLeft, Download } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { accountDeltas, roundMoney } from "@/lib/txn";
import { compareTxnChrono, toDate } from "@/lib/derive";
import { downloadCsv, toCsv } from "@/lib/csv";
import { lineTypeLabel } from "@/lib/lineTypes";
import { cn, formatDate, formatMoney } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  TableBody,
  TableCell,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { ResizableTable, ResizableHead } from "@/components/ResizableTable";
import { useColumnPrefs, type ColumnDef } from "@/lib/useColumnPrefs";
import { EmptyState, ErrorState, LoadingState } from "@/components/states";
import type { Account } from "@/types/models";

const TYPE_LABELS: Record<Account["type"], string> = {
  cash: "Cash",
  bank: "Bank",
  credit_card: "Credit Card",
};

function maskedId(a: Account): string | null {
  if (a.cardLast4) return `•••• ${a.cardLast4}`;
  if (a.accountNumber) return `••••${a.accountNumber.slice(-4)}`;
  return null;
}

// Ledger columns exist only to drive persisted, drag-resizable widths
// (all are always shown — no visibility toggling here).
type LedgerCol = "date" | "description" | "type" | "amount" | "balance";
const LEDGER_COLUMNS: ColumnDef<LedgerCol>[] = [
  { key: "date", label: "Date", defaultVisible: true, locked: true },
  { key: "description", label: "Description", defaultVisible: true, locked: true },
  { key: "type", label: "Type", defaultVisible: true, locked: true },
  { key: "amount", label: "Amount", defaultVisible: true, locked: true },
  { key: "balance", label: "Balance", defaultVisible: true, locked: true },
];

export function AccountLedger() {
  const { accountId } = useParams<{ accountId: string }>();
  const cols = useColumnPrefs<LedgerCol>("account-ledger", LEDGER_COLUMNS);
  const { activeWorkspace, can } = useWorkspace();
  const { accounts, debtsById, transactions, balanceOf, loading, error } = useData();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const canExport = can("reports.export");

  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  const account = accountId ? accounts.find((a) => a.id === accountId) : undefined;

  // Build the running-balance statement, oldest first, over ALL of this
  // account's transactions — then apply the date filter for display so the
  // running balance stays correct (it always accrues from the opening balance).
  const rows = useMemo(() => {
    if (!account) return [];
    const mine = transactions
      .filter((t) => {
        const d = accountDeltas(t, debtsById);
        return account.id in d && d[account.id] !== 0;
      })
      .sort(compareTxnChrono); // oldest first

    let running = account.openingBalance;
    const fromTime = from ? new Date(from).getTime() : -Infinity;
    const toTime = to ? new Date(to).getTime() + 86_400_000 - 1 : Infinity; // inclusive day

    const out: Array<{
      id: string;
      date: Date;
      description: string;
      types: string;
      delta: number;
      balance: number;
    }> = [];
    for (const t of mine) {
      const delta = accountDeltas(t, debtsById)[account.id] ?? 0;
      running = roundMoney(running + delta);
      const when = toDate(t.date);
      if (when.getTime() < fromTime || when.getTime() > toTime) continue;
      out.push({
        id: t.id,
        date: when,
        description: t.note ?? "—",
        types: [...new Set(t.lines.map((l) => lineTypeLabel(l.type)))].join(", "),
        delta,
        balance: running,
      });
    }
    return out.reverse(); // newest first for display
  }, [account, transactions, debtsById, from, to]);

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;
  if (!account) {
    return (
      <div>
        <BackLink />
        <EmptyState title="Account not found" hint="It may have been deleted." />
      </div>
    );
  }

  const balance = balanceOf(account.id);
  const isCard = account.type === "credit_card";

  function exportCsv() {
    downloadCsv(
      `ledger-${account!.name.replace(/\s+/g, "-").toLowerCase()}.csv`,
      toCsv(
        // CSV in chronological order (oldest first) reads like a statement.
        [...rows].reverse().map((r) => ({
          date: formatDate(r.date),
          description: r.description,
          type: r.types,
          amount: r.delta,
          balance: r.balance,
        })),
      ),
    );
  }

  return (
    <div>
      <BackLink />

      {/* Header */}
      <div className="mb-4">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold tracking-tight">{account.name}</h1>
          <Badge variant="secondary">{TYPE_LABELS[account.type]}</Badge>
          {maskedId(account) && (
            <span className="text-sm tabular-nums text-muted-foreground">{maskedId(account)}</span>
          )}
        </div>
      </div>

      {/* Balance summary */}
      <div className="mb-4 grid grid-cols-2 gap-3 sm:max-w-md">
        <div className="rounded-xl border bg-card p-3">
          <p className="text-xs uppercase tracking-wide text-muted-foreground">Opening balance</p>
          <p className="mt-1 truncate font-strong text-lg tabular-nums sm:text-xl">
            {formatMoney(account.openingBalance, currency)}
          </p>
        </div>
        <div className="rounded-xl border bg-card p-3">
          <p className="text-xs uppercase tracking-wide text-muted-foreground">Current balance</p>
          <p
            className={cn(
              "mt-1 truncate font-strong text-lg tabular-nums sm:text-xl",
              balance < 0 && "text-destructive",
            )}
          >
            {isCard && balance < 0
              ? `${formatMoney(-balance, currency)} owed`
              : formatMoney(balance, currency)}
          </p>
        </div>
      </div>

      {/* Filters + export */}
      <div className="mb-4 flex flex-wrap items-end gap-3">
        <div className="space-y-1">
          <Label htmlFor="led-from" className="text-xs text-muted-foreground">From</Label>
          <Input
            id="led-from"
            type="date"
            value={from}
            max={to || undefined}
            onChange={(e) => setFrom(e.target.value)}
            className="h-9 w-40"
          />
        </div>
        <div className="space-y-1">
          <Label htmlFor="led-to" className="text-xs text-muted-foreground">To</Label>
          <Input
            id="led-to"
            type="date"
            value={to}
            min={from || undefined}
            onChange={(e) => setTo(e.target.value)}
            className="h-9 w-40"
          />
        </div>
        {(from || to) && (
          <Button variant="ghost" size="sm" onClick={() => { setFrom(""); setTo(""); }}>
            Clear
          </Button>
        )}
        {canExport && rows.length > 0 && (
          <Button variant="outline" size="sm" className="ml-auto" onClick={exportCsv}>
            <Download className="h-4 w-4" /> Export CSV
          </Button>
        )}
      </div>

      {rows.length === 0 ? (
        <EmptyState
          title="No entries"
          hint={
            from || to
              ? "No transactions in this date range."
              : "Transactions that move this account will appear here."
          }
        />
      ) : (
        <ResizableTable prefs={cols} className="[&_td]:truncate">
          <TableHeader>
            <TableRow>
              <ResizableHead colKey="date">Date</ResizableHead>
              <ResizableHead colKey="description">Description</ResizableHead>
              <ResizableHead colKey="type" className="hidden sm:table-cell">Type</ResizableHead>
              <ResizableHead colKey="amount" className="text-right">Amount</ResizableHead>
              <ResizableHead colKey="balance" className="text-right">Balance</ResizableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="whitespace-nowrap text-muted-foreground">
                  {formatDate(r.date)}
                </TableCell>
                <TableCell>
                  <span className="block truncate">{r.description}</span>
                  <span className="text-xs text-muted-foreground sm:hidden">{r.types}</span>
                </TableCell>
                <TableCell className="hidden text-muted-foreground sm:table-cell">{r.types}</TableCell>
                <TableCell
                  className={cn(
                    "text-right tabular-nums",
                    r.delta < 0 ? "text-destructive" : "text-emerald-600 dark:text-emerald-400",
                  )}
                >
                  {formatMoney(r.delta, currency)}
                </TableCell>
                <TableCell className="text-right font-strong tabular-nums">
                  {formatMoney(r.balance, currency)}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </ResizableTable>
      )}
    </div>
  );
}

function BackLink() {
  return (
    <Link
      to="/settings/accounts"
      className="mb-2 inline-flex items-center gap-1 text-sm text-muted-foreground hover:underline"
    >
      <ArrowLeft className="h-4 w-4" /> Accounts
    </Link>
  );
}
