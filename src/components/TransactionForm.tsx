// Multi-line transaction entry (§6.3). The core engine UI:
//   - header: date, account, contact, note
//   - dynamic line rows: type + amount + conditional (category / debt / toAccount)
//     + optional per-line tax block
//   - live validation + signed total reconciliation
//   - quick templates: Loan repayment, Self transfer, Salary
//
// Submits a normalized TransactionInput; the caller persists it.

import { useMemo, useState } from "react";
import { Plus, Trash2 } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import type {
  Category,
  LineType,
  TaxHead,
  Transaction,
  TransactionLine,
} from "@/types/models";
import type { TransactionInput } from "@/data/mutations";
import { computeTotal, validateTransaction } from "@/lib/txn";
import { LINE_TYPE_LABELS } from "@/lib/lineTypes";
import { financialYearOf } from "@/lib/financialYear";
import { toDate } from "@/lib/derive";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { cn, formatMoney } from "@/lib/utils";

// LINE_TYPE_LABELS lives in @/lib/lineTypes so the detail dialog can reuse it.

const NEEDS_CATEGORY: LineType[] = [
  "income",
  "expense",
  "interest_income",
  "interest_expense",
  "fee",
  "tax",
];
const NEEDS_DEBT: LineType[] = ["borrow", "lend", "repayment"];
const CAN_TAX: LineType[] = ["income", "interest_income"];

let lineSeq = 0;
function blankLine(type: LineType = "expense"): TransactionLine {
  return { lineId: `l${++lineSeq}_${Date.now()}`, type, amount: 0 };
}

function categoryFor(line: TransactionLine, categories: Category[]): Category[] {
  // income lines pick income categories; everything else expense categories.
  const kind = line.type === "income" || line.type === "interest_income" ? "income" : "expense";
  return categories.filter((c) => c.kind === kind);
}

export interface TransactionFormInitial {
  txn?: Transaction;
  presetLines?: TransactionLine[];
  presetContactId?: string;
  presetAccountId?: string;
  lockContact?: boolean;
}

export function TransactionFormDialog({
  open,
  onClose,
  onSubmit,
  title = "New transaction",
  initial,
}: {
  open: boolean;
  onClose: () => void;
  onSubmit: (input: TransactionInput) => Promise<void>;
  title?: string;
  initial?: TransactionFormInitial;
}) {
  const { activeWorkspace } = useWorkspace();
  const { accounts, categories, contacts, debts, debtsById } = useData();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const fyStartMonth = activeWorkspace?.fyStartMonth ?? 4;

  const txn = initial?.txn;
  const [date, setDate] = useState(
    txn ? toDate(txn.date).toISOString().slice(0, 10) : new Date().toISOString().slice(0, 10),
  );
  const [accountId, setAccountId] = useState(
    txn?.accountId ?? initial?.presetAccountId ?? accounts[0]?.id ?? "",
  );
  const [contactId, setContactId] = useState(
    txn?.contactId ?? initial?.presetContactId ?? "",
  );
  const [note, setNote] = useState(txn?.note ?? "");
  const [lines, setLines] = useState<TransactionLine[]>(
    txn?.lines ?? initial?.presetLines ?? [blankLine()],
  );
  const [busy, setBusy] = useState(false);

  const total = useMemo(() => computeTotal(lines, debtsById), [lines, debtsById]);
  const issues = useMemo(
    () => validateTransaction({ accountId, contactId: contactId || undefined, lines }, debtsById),
    [accountId, contactId, lines, debtsById],
  );
  const issuesByLine = useMemo(() => {
    const map = new Map<string, string[]>();
    for (const i of issues) {
      if (i.lineId) map.set(i.lineId, [...(map.get(i.lineId) ?? []), i.message]);
    }
    return map;
  }, [issues]);
  const headerIssues = issues.filter((i) => !i.lineId);

  function patchLine(lineId: string, patch: Partial<TransactionLine>) {
    setLines((ls) => ls.map((l) => (l.lineId === lineId ? { ...l, ...patch } : l)));
  }
  function changeType(lineId: string, type: LineType) {
    setLines((ls) =>
      ls.map((l) =>
        l.lineId === lineId
          ? { lineId: l.lineId, type, amount: l.amount, note: l.note }
          : l,
      ),
    );
  }
  function addLine() {
    setLines((ls) => [...ls, blankLine()]);
  }
  function removeLine(lineId: string) {
    setLines((ls) => (ls.length > 1 ? ls.filter((l) => l.lineId !== lineId) : ls));
  }

  // ---- templates ----
  function applyTemplate(kind: "repayment" | "transfer" | "salary") {
    if (kind === "repayment") {
      setLines([
        blankLine("repayment"),
        blankLine("interest_expense"),
        blankLine("fee"),
        blankLine("tax"),
      ]);
    } else if (kind === "transfer") {
      setLines([blankLine("transfer_out"), blankLine("transfer_in")]);
    } else {
      const salary = blankLine("income");
      salary.tax = { taxable: true, head: "salary", tdsAmount: 0, taxInclusive: false };
      setLines([salary]);
    }
  }

  async function submit() {
    if (issues.length > 0 || !accountId) return;
    setBusy(true);
    try {
      const fy = financialYearOf(new Date(date), fyStartMonth);
      await onSubmit({
        date: new Date(date),
        note: note.trim() || undefined,
        accountId,
        contactId: contactId || undefined,
        totalAmount: total,
        financialYear: fy,
        lines: lines.map((l) => ({
          ...l,
          amount: Number(l.amount) || 0,
        })),
      });
      onClose();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-3xl">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
        </DialogHeader>

        {/* templates */}
        <div className="flex flex-wrap gap-2">
          <span className="text-xs text-muted-foreground self-center">Templates:</span>
          <Button size="sm" variant="outline" onClick={() => applyTemplate("repayment")}>
            Loan repayment
          </Button>
          <Button size="sm" variant="outline" onClick={() => applyTemplate("transfer")}>
            Self transfer
          </Button>
          <Button size="sm" variant="outline" onClick={() => applyTemplate("salary")}>
            Salary
          </Button>
        </div>

        {/* header */}
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <Label>Date</Label>
            <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label>Account</Label>
            <Select value={accountId} onValueChange={setAccountId}>
              <SelectTrigger>
                <SelectValue placeholder="Select account" />
              </SelectTrigger>
              <SelectContent>
                {accounts.map((a) => (
                  <SelectItem key={a.id} value={a.id}>
                    {a.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Contact (optional)</Label>
            <Select
              value={contactId || "__none"}
              onValueChange={(v) => setContactId(v === "__none" ? "" : v)}
              disabled={initial?.lockContact}
            >
              <SelectTrigger>
                <SelectValue placeholder="No contact" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="__none">No contact</SelectItem>
                {contacts.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label>Note (optional)</Label>
            <Input value={note} onChange={(e) => setNote(e.target.value)} />
          </div>
        </div>

        {/* lines */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <Label>Lines</Label>
            <Button size="sm" variant="ghost" onClick={addLine}>
              <Plus /> Add line
            </Button>
          </div>
          {lines.map((line) => {
            const lineIssues = issuesByLine.get(line.lineId) ?? [];
            return (
              <div
                key={line.lineId}
                className={cn(
                  "rounded-md border p-3 space-y-2",
                  lineIssues.length > 0 && "border-destructive/50",
                )}
              >
                <div className="flex flex-wrap items-end gap-2">
                  <div className="w-40 space-y-1">
                    <Label className="text-xs">Type</Label>
                    <Select
                      value={line.type}
                      onValueChange={(v) => changeType(line.lineId, v as LineType)}
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {(Object.keys(LINE_TYPE_LABELS) as LineType[]).map((t) => (
                          <SelectItem key={t} value={t}>
                            {LINE_TYPE_LABELS[t]}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="w-32 space-y-1">
                    <Label className="text-xs">Amount</Label>
                    <Input
                      type="number"
                      min="0"
                      step="0.01"
                      value={line.amount || ""}
                      onChange={(e) =>
                        patchLine(line.lineId, { amount: Number(e.target.value) })
                      }
                    />
                  </div>

                  {NEEDS_CATEGORY.includes(line.type) && (
                    <div className="w-44 space-y-1">
                      <Label className="text-xs">Category</Label>
                      <Select
                        value={line.categoryId ?? ""}
                        onValueChange={(v) => patchLine(line.lineId, { categoryId: v })}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Select" />
                        </SelectTrigger>
                        <SelectContent>
                          {categoryFor(line, categories).map((c) => (
                            <SelectItem key={c.id} value={c.id}>
                              {c.name}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  )}

                  {NEEDS_DEBT.includes(line.type) && (
                    <div className="w-48 space-y-1">
                      <Label className="text-xs">Debt</Label>
                      <Select
                        value={line.debtId ?? ""}
                        onValueChange={(v) => patchLine(line.lineId, { debtId: v })}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Select debt" />
                        </SelectTrigger>
                        <SelectContent>
                          {debts
                            .filter((d) => !contactId || d.contactId === contactId)
                            .map((d) => (
                              <SelectItem key={d.id} value={d.id}>
                                {d.label ?? d.purpose} ({d.direction})
                              </SelectItem>
                            ))}
                        </SelectContent>
                      </Select>
                    </div>
                  )}

                  {line.type === "transfer_in" && (
                    <div className="w-44 space-y-1">
                      <Label className="text-xs">To account</Label>
                      <Select
                        value={line.toAccountId ?? ""}
                        onValueChange={(v) => patchLine(line.lineId, { toAccountId: v })}
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Destination" />
                        </SelectTrigger>
                        <SelectContent>
                          {accounts
                            .filter((a) => a.id !== accountId)
                            .map((a) => (
                              <SelectItem key={a.id} value={a.id}>
                                {a.name}
                              </SelectItem>
                            ))}
                        </SelectContent>
                      </Select>
                    </div>
                  )}

                  <Button
                    size="icon"
                    variant="ghost"
                    onClick={() => removeLine(line.lineId)}
                    disabled={lines.length === 1}
                    className="mb-0.5"
                  >
                    <Trash2 />
                  </Button>
                </div>

                {/* tax block */}
                {CAN_TAX.includes(line.type) && (
                  <TaxBlock
                    line={line}
                    onChange={(tax) => patchLine(line.lineId, { tax })}
                  />
                )}

                {lineIssues.map((m, i) => (
                  <p key={i} className="text-xs text-destructive">
                    {m}
                  </p>
                ))}
              </div>
            );
          })}

          {/* Add-line button at the end so it's reachable without scrolling up */}
          <Button
            type="button"
            variant="outline"
            className="w-full border-dashed"
            onClick={addLine}
          >
            <Plus className="h-4 w-4" /> Add line
          </Button>
        </div>

        {/* footer: total + header issues */}
        <div className="space-y-1">
          {headerIssues.map((i, idx) => (
            <p key={idx} className="text-xs text-destructive">
              {i.message}
            </p>
          ))}
          <div className="flex items-center justify-between border-t pt-2">
            <span className="text-sm text-muted-foreground">Net on account</span>
            <span
              className={cn(
                "font-strong text-lg tabular-nums",
                total < 0 && "text-destructive",
                total > 0 && "text-green-600",
              )}
            >
              {formatMoney(total, currency)}
            </span>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void submit()} disabled={busy || issues.length > 0}>
            {busy ? "Saving…" : "Save transaction"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function TaxBlock({
  line,
  onChange,
}: {
  line: TransactionLine;
  onChange: (tax: TransactionLine["tax"]) => void;
}) {
  const tax = line.tax;
  const enabled = !!tax;

  return (
    <div className="rounded bg-muted/50 p-2">
      <label className="flex items-center gap-2 text-xs">
        <input
          type="checkbox"
          checked={enabled}
          onChange={(e) =>
            onChange(
              e.target.checked
                ? { taxable: true, head: "other", tdsAmount: 0, taxInclusive: false }
                : undefined,
            )
          }
        />
        Tax info
      </label>
      {enabled && tax && (
        <div className="mt-2 flex flex-wrap items-end gap-2">
          <div className="space-y-1">
            <Label className="text-xs">Head</Label>
            <Select
              value={tax.head}
              onValueChange={(v) => onChange({ ...tax, head: v as TaxHead })}
            >
              <SelectTrigger className="h-8 w-36">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {(["salary", "interest", "capital_gains", "other", "exempt"] as TaxHead[]).map(
                  (h) => (
                    <SelectItem key={h} value={h}>
                      {h}
                    </SelectItem>
                  ),
                )}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1">
            <Label className="text-xs">TDS</Label>
            <Input
              type="number"
              className="h-8 w-24"
              value={tax.tdsAmount || ""}
              onChange={(e) => onChange({ ...tax, tdsAmount: Number(e.target.value) })}
            />
          </div>
          <label className="flex items-center gap-1 text-xs">
            <input
              type="checkbox"
              checked={tax.taxable}
              onChange={(e) => onChange({ ...tax, taxable: e.target.checked })}
            />
            Taxable
          </label>
          <Badge variant="outline" className="mb-1">
            {tax.taxable ? "Counts in FY tax" : "Excluded"}
          </Badge>
        </div>
      )}
    </div>
  );
}
