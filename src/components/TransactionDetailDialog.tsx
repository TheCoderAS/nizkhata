// Shared transaction detail modal. Self-contained: resolves account / contact /
// category names from the workspace data, renders the header fields + a lines
// table + audit/history. Any screen can open it by passing a `txn`; optional
// onEdit/onDelete add those actions to the kebab.

import { useData } from "@/data/WorkspaceDataProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { DetailDialog, type DetailField } from "@/components/DetailDialog";
import { EXTERNAL_ACCOUNT } from "@/data/mutations";
import { type RowAction } from "@/components/RowActions";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Pencil, Trash2 } from "lucide-react";
import type { Transaction } from "@/types/models";
import { toDate } from "@/lib/derive";
import { lineTypeLabel } from "@/lib/lineTypes";
import { taxHeadLabel } from "@/lib/taxHeads";
import { cn, formatDate, formatMoney } from "@/lib/utils";

export function TransactionDetailDialog({
  txn,
  onClose,
  onEdit,
  onDelete,
}: {
  txn: Transaction;
  onClose: () => void;
  onEdit?: (t: Transaction) => void;
  onDelete?: (t: Transaction) => void;
}) {
  const { activeWorkspace } = useWorkspace();
  const { accountsById, contactsById, categoriesById } = useData();
  const currency = activeWorkspace?.baseCurrency ?? "INR";

  const accountName = (id: string) =>
    accountsById[id]?.name ?? (id === EXTERNAL_ACCOUNT ? "External" : "—");

  const fields: DetailField[] = [
    { label: "Date", value: formatDate(toDate(txn.date)) },
    { label: "Account", value: accountName(txn.accountId) },
    {
      label: "Contact",
      value: txn.contactId ? contactsById[txn.contactId]?.name ?? "—" : "—",
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

  const actions: RowAction[] = [
    onEdit && { label: "Edit", icon: Pencil, onSelect: () => onEdit(txn) },
    onDelete && {
      label: "Delete",
      icon: Trash2,
      onSelect: () => onDelete(txn),
      destructive: true,
      separatorBefore: true,
    },
  ].filter(Boolean) as RowAction[];

  return (
    <DetailDialog
      open
      onClose={onClose}
      title="Transaction"
      fields={fields}
      actions={actions}
      entityId={txn.id}
      audit={{
        createdBy: txn.createdBy,
        createdAt: txn.createdAt,
        updatedBy: txn.updatedBy,
        updatedAt: txn.updatedAt,
      }}
    >
      <div className="mt-2">
        <p className="mb-2 text-sm font-medium">Lines</p>
        <div className="overflow-hidden rounded-md border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Type</TableHead>
                <TableHead>Category / Detail</TableHead>
                <TableHead className="text-right">Amount</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {txn.lines.map((l) => {
                const detail = l.categoryId
                  ? categoriesById[l.categoryId]?.name ?? "—"
                  : l.toAccountId
                    ? `→ ${accountName(l.toAccountId)}`
                    : l.note ?? "—";
                return (
                  <TableRow key={l.lineId}>
                    <TableCell>
                      <div className="flex flex-wrap items-center gap-1">
                        <Badge variant="secondary" className="text-[10px]">
                          {lineTypeLabel(l.type)}
                        </Badge>
                        {l.external && (
                          <Badge variant="outline" className="text-[10px]">
                            external
                          </Badge>
                        )}
                        {l.tax?.taxable && (
                          <Badge variant="outline" className="text-[10px]">
                            tax: {taxHeadLabel(l.tax.head)}
                          </Badge>
                        )}
                      </div>
                    </TableCell>
                    <TableCell className="text-muted-foreground">{detail}</TableCell>
                    <TableCell className="text-right tabular-nums">
                      {formatMoney(l.amount, currency)}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </div>
      </div>
    </DetailDialog>
  );
}
