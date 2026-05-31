// Reports (§6.9). Per-category, per-contact, and FY tax summary (taxable lines by
// head + total TDS, auto-excluding debts/transfers). CSV export gated by
// reports.export.

import { useMemo, useState } from "react";
import { Download } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import {
  fyTaxSummary,
  spendByCategory,
  toDate,
} from "@/lib/derive";
import { financialYearOf } from "@/lib/financialYear";
import { downloadCsv, toCsv } from "@/lib/csv";
import { taxHeadLabel } from "@/lib/taxHeads";
import { PageHeader } from "@/components/PageHeader";
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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { EmptyState, ErrorState, LoadingState } from "@/components/states";
import { formatMoney } from "@/lib/utils";

export function Reports() {
  const { activeWorkspace, can } = useWorkspace();
  const { transactions, categories, contacts, loading, error } = useData();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const fyStartMonth = activeWorkspace?.fyStartMonth ?? 4;
  const canExport = can("reports.export");

  // Distinct FYs present in the data, plus the current one.
  const fyOptions = useMemo(() => {
    const set = new Set<string>();
    set.add(financialYearOf(new Date(), fyStartMonth));
    for (const t of transactions) set.add(financialYearOf(toDate(t.date), fyStartMonth));
    return [...set].sort().reverse();
  }, [transactions, fyStartMonth]);

  const [fy, setFy] = useState(fyOptions[0] ?? financialYearOf(new Date(), fyStartMonth));

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
      name: contacts.find((c) => c.id === id)?.name ?? "—",
      ...v,
    }));
  }, [transactions, contacts, fy, fyStartMonth]);

  const tax = useMemo(
    () => fyTaxSummary(transactions, fy, fyStartMonth),
    [transactions, fy, fyStartMonth],
  );

  if (loading) return <LoadingState />;
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

      <Tabs defaultValue="tax">
        <TabsList>
          <TabsTrigger value="tax">FY tax summary</TabsTrigger>
          <TabsTrigger value="category">By category</TabsTrigger>
          <TabsTrigger value="contact">By contact</TabsTrigger>
        </TabsList>

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
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Head</TableHead>
                    <TableHead className="text-right">Taxable amount</TableHead>
                    <TableHead className="text-right">TDS</TableHead>
                    <TableHead className="text-right">Lines</TableHead>
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
              </Table>
            </>
          )}
          <p className="text-xs text-muted-foreground">
            v1 captures taxable flags and produces this summary; slab/regime
            computation is a later, jurisdiction-specific layer.
          </p>
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
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Category</TableHead>
                    <TableHead className="text-right">Amount</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {byCategory.map((c) => (
                    <TableRow key={c.categoryId}>
                      <TableCell className="font-medium">{c.name}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        {formatMoney(c.amount, currency)}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
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
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Contact</TableHead>
                    <TableHead className="text-right">Received</TableHead>
                    <TableHead className="text-right">Paid</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {byContact.map((c) => (
                    <TableRow key={c.name}>
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
              </Table>
            </>
          )}
        </TabsContent>
      </Tabs>
    </div>
  );
}
