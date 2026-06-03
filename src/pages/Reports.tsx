// Reports (§6.9). Per-category, per-contact, and FY tax summary (taxable lines by
// head + total TDS, auto-excluding debts/transfers). CSV export gated by
// reports.export.

import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Download } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import {
  fyTaxSummary,
  spendByCategory,
  periodTotals,
  toDate,
} from "@/lib/derive";
import { financialYearOf } from "@/lib/financialYear";
import { trendSeries } from "@/lib/period";
import { downloadCsv, toCsv } from "@/lib/csv";
import { taxHeadLabel } from "@/lib/taxHeads";
import { txnsByCategory, txnsByContact } from "@/lib/links";
import { PageHeader } from "@/components/PageHeader";
import { TrendChart } from "@/components/TrendChart";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  TableBody,
  TableCell,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { ResizableTable, ResizableHead } from "@/components/ResizableTable";
import { useColumnWidths } from "@/lib/useColumnWidths";
import { EmptyState, ErrorState, PageSkeleton } from "@/components/states";
import { cn, formatMoney } from "@/lib/utils";

export function Reports() {
  const navigate = useNavigate();
  const taxWidths = useColumnWidths("report-tax");
  const catWidths = useColumnWidths("report-category");
  const contactWidths = useColumnWidths("report-contact");
  const { activeWorkspace, can } = useWorkspace();
  const { transactions, categories, contacts, loading, error } = useData();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const fyStartMonth = activeWorkspace?.fyStartMonth ?? 4;
  const canExport = can("reports.export");
  const canViewTxns = can("transactions.view");

  // Distinct FYs present in the data, plus the current one.
  const fyOptions = useMemo(() => {
    const set = new Set<string>();
    set.add(financialYearOf(new Date(), fyStartMonth));
    for (const t of transactions) set.add(financialYearOf(toDate(t.date), fyStartMonth));
    return [...set].sort().reverse();
  }, [transactions, fyStartMonth]);

  const [fy, setFy] = useState(fyOptions[0] ?? financialYearOf(new Date(), fyStartMonth));

  // Date range for the selected FY string (e.g. "2026-27") so the trend chart
  // can bucket income/expense across that financial year.
  const fyRange = useMemo(() => {
    const startYear = Number(fy.slice(0, 4));
    const start = new Date(startYear, fyStartMonth - 1, 1);
    const end = new Date(startYear + 1, fyStartMonth - 1, 1);
    return { start, end };
  }, [fy, fyStartMonth]);

  const trend = useMemo(() => trendSeries(transactions, fyRange), [transactions, fyRange]);
  const totals = useMemo(
    () => periodTotals(transactions, (d) => d >= fyRange.start && d < fyRange.end),
    [transactions, fyRange],
  );
  const savingsRate =
    totals.income > 0 ? Math.round((totals.net / totals.income) * 100) : 0;

  const byCategory = useMemo(
    () => spendByCategory(transactions, categories, fy, fyStartMonth),
    [transactions, categories, fy, fyStartMonth],
  );

  const byContact = useMemo(() => {
    const totals = new Map<string, { inAmt: number; outAmt: number }>();
    for (const t of transactions) {
      if (!t.contactId) continue;
      if (financialYearOf(toDate(t.date), fyStartMonth) !== fy) continue;
      const cur = totals.get(t.contactId) ?? { inAmt: 0, outAmt: 0 };
      if (t.totalAmount >= 0) cur.inAmt += t.totalAmount;
      else cur.outAmt += -t.totalAmount;
      totals.set(t.contactId, cur);
    }
    return [...totals.entries()].map(([id, v]) => ({
      id,
      name: contacts.find((c) => c.id === id)?.name ?? "—",
      ...v,
    }));
  }, [transactions, contacts, fy, fyStartMonth]);

  const tax = useMemo(
    () => fyTaxSummary(transactions, fy, fyStartMonth),
    [transactions, fy, fyStartMonth],
  );

  if (loading) return <PageSkeleton />;
  if (error) return <ErrorState message={error} />;

  return (
    <div>
      <PageHeader
        title="Reports"
        actions={
          <Select value={fy} onValueChange={setFy}>
            <SelectTrigger className="w-36">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {fyOptions.map((f) => (
                <SelectItem key={f} value={f}>
                  FY {f}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        }
      />

      <Tabs defaultValue="insights">
        <TabsList>
          <TabsTrigger value="insights">Insights</TabsTrigger>
          <TabsTrigger value="tax">FY tax summary</TabsTrigger>
          <TabsTrigger value="category">By category</TabsTrigger>
          <TabsTrigger value="contact">By contact</TabsTrigger>
        </TabsList>

        {/* ---- insights ---- */}
        <TabsContent value="insights" className="space-y-4">
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <InsightStat label="Income" value={formatMoney(totals.income, currency)} tone="pos" />
            <InsightStat label="Expense" value={formatMoney(totals.expense, currency)} tone="neg" />
            <InsightStat
              label="Net"
              value={formatMoney(totals.net, currency)}
              tone={totals.net >= 0 ? "pos" : "neg"}
            />
            <InsightStat label="Savings rate" value={`${savingsRate}%`} tone={savingsRate >= 0 ? "pos" : "neg"} />
          </div>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Income vs expense · FY {fy}</CardTitle>
            </CardHeader>
            <CardContent>
              <TrendChart data={trend.buckets} currency={currency} />
            </CardContent>
          </Card>
        </TabsContent>

        {/* ---- tax ---- */}
        <TabsContent value="tax" className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm text-muted-foreground">Total taxable</CardTitle>
              </CardHeader>
              <CardContent className="text-2xl font-semibold tabular-nums">
                {formatMoney(tax.totalTaxable, currency)}
              </CardContent>
            </Card>
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm text-muted-foreground">Total TDS</CardTitle>
              </CardHeader>
              <CardContent className="text-2xl font-semibold tabular-nums">
                {formatMoney(tax.totalTds, currency)}
              </CardContent>
            </Card>
          </div>

          {tax.byHead.length === 0 ? (
            <EmptyState title="No taxable lines this FY" />
          ) : (
            <>
              {canExport && (
                <div className="flex justify-end">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() =>
                      downloadCsv(
                        `tax-summary-${fy}.csv`,
                        toCsv(
                          tax.byHead.map((h) => ({
                            head: taxHeadLabel(h.head),
                            taxableAmount: h.taxableAmount,
                            tdsAmount: h.tdsAmount,
                            lines: h.lineCount,
                          })),
                        ),
                      )
                    }
                  >
                    <Download /> Export CSV
                  </Button>
                </div>
              )}
              <ResizableTable prefs={taxWidths} className="[&_td]:truncate">
                <TableHeader>
                  <TableRow>
                    <ResizableHead colKey="head">Head</ResizableHead>
                    <ResizableHead colKey="taxable" className="text-right">Taxable amount</ResizableHead>
                    <ResizableHead colKey="tds" className="text-right">TDS</ResizableHead>
                    <ResizableHead colKey="lines" className="text-right">Lines</ResizableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {tax.byHead.map((h) => (
                    <TableRow key={h.head}>
                      <TableCell className="font-medium">{taxHeadLabel(h.head)}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        {formatMoney(h.taxableAmount, currency)}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">
                        {formatMoney(h.tdsAmount, currency)}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{h.lineCount}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </ResizableTable>
            </>
          )}
        </TabsContent>

        {/* ---- by category ---- */}
        <TabsContent value="category" className="space-y-4">
          {byCategory.length === 0 ? (
            <EmptyState title="No spend this FY" />
          ) : (
            <>
              {canExport && (
                <div className="flex justify-end">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() =>
                      downloadCsv(
                        `spend-by-category-${fy}.csv`,
                        toCsv(byCategory.map((c) => ({ category: c.name, amount: c.amount }))),
                      )
                    }
                  >
                    <Download /> Export CSV
                  </Button>
                </div>
              )}
              <ResizableTable prefs={catWidths} className="[&_td]:truncate">
                <TableHeader>
                  <TableRow>
                    <ResizableHead colKey="category">Category</ResizableHead>
                    <ResizableHead colKey="amount" className="text-right">Amount</ResizableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {byCategory.map((c) => (
                    <TableRow
                      key={c.categoryId}
                      onClick={canViewTxns ? () => navigate(txnsByCategory(c.categoryId)) : undefined}
                      className={canViewTxns ? "cursor-pointer" : undefined}
                    >
                      <TableCell className="font-medium">{c.name}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        {formatMoney(c.amount, currency)}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </ResizableTable>
            </>
          )}
        </TabsContent>

        {/* ---- by contact ---- */}
        <TabsContent value="contact" className="space-y-4">
          {byContact.length === 0 ? (
            <EmptyState title="No contact activity this FY" />
          ) : (
            <>
              {canExport && (
                <div className="flex justify-end">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() =>
                      downloadCsv(
                        `by-contact-${fy}.csv`,
                        toCsv(
                          byContact.map((c) => ({
                            contact: c.name,
                            received: c.inAmt,
                            paid: c.outAmt,
                          })),
                        ),
                      )
                    }
                  >
                    <Download /> Export CSV
                  </Button>
                </div>
              )}
              <ResizableTable prefs={contactWidths} className="[&_td]:truncate">
                <TableHeader>
                  <TableRow>
                    <ResizableHead colKey="contact">Contact</ResizableHead>
                    <ResizableHead colKey="received" className="text-right">Received</ResizableHead>
                    <ResizableHead colKey="paid" className="text-right">Paid</ResizableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {byContact.map((c) => (
                    <TableRow
                      key={c.id}
                      onClick={canViewTxns ? () => navigate(txnsByContact(c.id)) : undefined}
                      className={canViewTxns ? "cursor-pointer" : undefined}
                    >
                      <TableCell className="font-medium">{c.name}</TableCell>
                      <TableCell className="text-right tabular-nums text-green-600">
                        {formatMoney(c.inAmt, currency)}
                      </TableCell>
                      <TableCell className="text-right tabular-nums text-destructive">
                        {formatMoney(c.outAmt, currency)}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </ResizableTable>
            </>
          )}
        </TabsContent>
      </Tabs>
    </div>
  );
}

function InsightStat({
  label,
  value,
  tone,
}: {
  label: string;
  value: string;
  tone: "pos" | "neg";
}) {
  return (
    <div className="rounded-xl border bg-card p-3">
      <p className="text-xs text-muted-foreground">{label}</p>
      <p
        className={cn(
          "mt-1 truncate font-strong text-lg tabular-nums sm:text-xl",
          tone === "pos" ? "text-emerald-600 dark:text-emerald-400" : "text-destructive",
        )}
      >
        {value}
      </p>
    </div>
  );
}
