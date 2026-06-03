// A compact, reusable list of transactions linked to a due or a debt, shown
// inside that entity's detail dialog. Each row opens the transaction's own
// detail dialog, so you can navigate entity -> its settlement/related txns.
//
// Linkage uses the fields already on the data model:
//   - dues:  transaction.dueId === due.id
//   - debts: some transaction line has line.debtId === debt.id

import { useMemo, useState } from "react";
import { ArrowLeftRight } from "lucide-react";
import { useData } from "@/data/WorkspaceDataProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { compareTxnChrono, toDate } from "@/lib/derive";
import { cn, formatDate, formatMoney } from "@/lib/utils";
import { TransactionDetailDialog } from "@/components/TransactionDetailDialog";
import type { Transaction } from "@/types/models";

export function LinkedTransactions({
  /** match by due id (transaction.dueId) */
  dueId,
  /** match by debt id (any line.debtId) */
  debtId,
  emptyHint = "No linked transactions yet.",
}: {
  dueId?: string;
  debtId?: string;
  emptyHint?: string;
}) {
  const { transactions } = useData();
  const { activeWorkspace } = useWorkspace();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const [open, setOpen] = useState<Transaction | null>(null);

  const linked = useMemo(() => {
    const match = (t: Transaction) =>
      (dueId && t.dueId === dueId) ||
      (debtId && t.lines.some((l) => l.debtId === debtId));
    return transactions.filter(match).sort((a, b) => -compareTxnChrono(a, b));
  }, [transactions, dueId, debtId]);

  return (
    <div className="space-y-1.5">
      <p className="text-xs font-medium text-muted-foreground">
        Linked transactions{linked.length > 0 ? ` (${linked.length})` : ""}
      </p>
      {linked.length === 0 ? (
        <p className="text-xs text-muted-foreground">{emptyHint}</p>
      ) : (
        <div className="overflow-hidden rounded-lg border">
          {linked.map((t) => (
            <button
              key={t.id}
              type="button"
              onClick={() => setOpen(t)}
              className="flex w-full items-center gap-2 border-b px-3 py-2 text-left text-sm transition-colors last:border-b-0 hover:bg-accent"
            >
              <ArrowLeftRight className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
              <span className="min-w-0 flex-1 truncate">
                {t.note ?? "Transaction"}
                <span className="text-muted-foreground"> · {formatDate(toDate(t.date))}</span>
              </span>
              <span
                className={cn(
                  "shrink-0 tabular-nums",
                  t.totalAmount < 0 ? "text-destructive" : "text-emerald-600 dark:text-emerald-400",
                )}
              >
                {formatMoney(t.totalAmount, currency)}
              </span>
            </button>
          ))}
        </div>
      )}

      {open && <TransactionDetailDialog txn={open} onClose={() => setOpen(null)} />}
    </div>
  );
}
