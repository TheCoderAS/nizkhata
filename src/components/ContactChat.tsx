// Chat-style transaction timeline for a contact. Transactions render as
// chronological message bubbles (oldest -> newest) with date separators:
//   - money IN (you received)  -> left,  green accent
//   - money OUT (you paid)     -> right, primary accent
// Debt-linked lines surface the debt label inline, so transactions + debts read
// as one conversation. Tapping a bubble opens the shared transaction detail
// modal.

import { useMemo, useState } from "react";
import { useData } from "@/data/WorkspaceDataProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { TransactionDetailDialog } from "@/components/TransactionDetailDialog";
import { Badge } from "@/components/ui/badge";
import { EmptyState } from "@/components/states";
import type { Transaction } from "@/types/models";
import { toDate, compareTxnChrono } from "@/lib/derive";
import { cn, formatDate, formatMoney } from "@/lib/utils";

export function ContactChat({ contactId }: { contactId: string }) {
  const { transactions, debtsById } = useData();
  const { activeWorkspace } = useWorkspace();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const [openTxn, setOpenTxn] = useState<Transaction | null>(null);

  // oldest -> newest, like a chat
  const items = useMemo(
    () =>
      transactions
        .filter((t) => t.contactId === contactId)
        .sort(compareTxnChrono),
    [transactions, contactId],
  );

  if (items.length === 0) {
    return <EmptyState title="No transactions with this contact yet" />;
  }

  let lastDay = "";

  return (
    <div className="space-y-2">
      {items.map((t) => {
        const day = formatDate(toDate(t.date));
        const showSep = day !== lastDay;
        lastDay = day;
        // money received from the contact reads as "incoming" (left)
        const incoming = t.totalAmount >= 0;

        const debtLabels = t.lines
          .filter((l) => l.debtId)
          .map((l) => debtsById[l.debtId!]?.label)
          .filter(Boolean) as string[];

        return (
          <div key={t.id}>
            {showSep && (
              <div className="my-3 flex justify-center">
                <span className="rounded-full bg-muted px-3 py-0.5 text-xs text-muted-foreground">
                  {day}
                </span>
              </div>
            )}
            <div className={cn("flex", incoming ? "justify-start" : "justify-end")}>
              <button
                onClick={() => setOpenTxn(t)}
                className={cn(
                  "max-w-[80%] rounded-2xl border px-3 py-2 text-left shadow-sm transition-colors sm:max-w-[70%]",
                  incoming
                    ? "rounded-tl-sm bg-card hover:bg-accent"
                    : "rounded-tr-sm bg-primary/10 hover:bg-primary/15",
                )}
              >
                <div
                  className={cn(
                    "text-base font-semibold tabular-nums",
                    incoming ? "text-green-600" : "text-destructive",
                  )}
                >
                  {incoming ? "+" : "−"}
                  {formatMoney(Math.abs(t.totalAmount), currency)}
                </div>
                {t.note && <p className="text-sm text-muted-foreground">{t.note}</p>}
                <div className="mt-1 flex flex-wrap items-center gap-1">
                  {t.lines.slice(0, 3).map((l) => (
                    <Badge key={l.lineId} variant="secondary" className="text-[10px]">
                      {l.type}
                    </Badge>
                  ))}
                  {debtLabels.map((label) => (
                    <Badge key={label} variant="outline" className="text-[10px]">
                      {label}
                    </Badge>
                  ))}
                </div>
              </button>
            </div>
          </div>
        );
      })}

      {openTxn && (
        <TransactionDetailDialog txn={openTxn} onClose={() => setOpenTxn(null)} />
      )}
    </div>
  );
}
