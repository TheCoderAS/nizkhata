// Dashboard (§6.2). Current FY & month income/expense/net; total in accounts vs
// held-for-others (custodial); spend-by-category; upcoming dues; recent txns.

import { useMemo } from "react";
import { Link } from "react-router-dom";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import {
  custodialHeld,
  dueStatusFromSettled,
  periodTotals,
  spendByCategory,
  toDate,
} from "@/lib/derive";
import { financialYearOf, financialYearRange } from "@/lib/financialYear";
import { PageHeader } from "@/components/PageHeader";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { ErrorState, LoadingState } from "@/components/states";
import { cn, formatDate, formatMoney } from "@/lib/utils";

export function Dashboard() {
  const { activeWorkspace } = useWorkspace();
  const { accounts, transactions, dues, debts, categories, balanceOf, settledOf, loading, error } =
    useData();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const fyStartMonth = activeWorkspace?.fyStartMonth ?? 4;
  const now = new Date();
  const fy = financialYearOf(now, fyStartMonth);

  const fyTotals = useMemo(() => {
    const { start, end } = financialYearRange(now, fyStartMonth);
    return periodTotals(transactions, (d) => d >= start && d < end);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [transactions, fyStartMonth]);

  const monthTotals = useMemo(() => {
    const mStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const mEnd = new Date(now.getFullYear(), now.getMonth() + 1, 1);
    return periodTotals(transactions, (d) => d >= mStart && d < mEnd);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [transactions]);

  const totalInAccounts = useMemo(
    () => accounts.reduce((s, a) => s + balanceOf(a.id), 0),
    [accounts, balanceOf],
  );
  const held = useMemo(() => custodialHeld(debts, transactions), [debts, transactions]);

  const topSpend = useMemo(
    () => spendByCategory(transactions, categories, fy, fyStartMonth).slice(0, 6),
    [transactions, categories, fy, fyStartMonth],
  );

  const upcoming = useMemo(
    () =>
      dues
        .filter((d) => {
          const status = dueStatusFromSettled(d, settledOf(d.id));
          return status === "open" || status === "partial";
        })
        .sort((a, b) => toDate(a.dueDate).getTime() - toDate(b.dueDate).getTime())
        .slice(0, 5),
    [dues, settledOf],
  );

  const recent = transactions.slice(0, 6);

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  return (
    <div>
      <PageHeader
        title="Dashboard"
        description={`${activeWorkspace?.name ?? ""} · FY ${fy}`}
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Metric label="Income (FY)" value={formatMoney(fyTotals.income, currency)} positive />
        <Metric label="Expense (FY)" value={formatMoney(fyTotals.expense, currency)} negative />
        <Metric
          label="Net (FY)"
          value={formatMoney(fyTotals.net, currency)}
          positive={fyTotals.net >= 0}
          negative={fyTotals.net < 0}
        />
        <Metric label="Net (this month)" value={formatMoney(monthTotals.net, currency)} />
      </div>

      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <Metric label="Total in accounts" value={formatMoney(totalInAccounts, currency)} />
        <Metric
          label="Held for others (custodial)"
          value={formatMoney(held, currency)}
          hint="Money you're holding that belongs to contacts"
        />
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Spend by category (FY)</CardTitle>
          </CardHeader>
          <CardContent>
            {topSpend.length === 0 ? (
              <p className="text-sm text-muted-foreground">No spend recorded.</p>
            ) : (
              <div className="space-y-2">
                {topSpend.map((c) => {
                  const max = topSpend[0].amount || 1;
                  return (
                    <div key={c.categoryId}>
                      <div className="flex justify-between text-sm">
                        <span>{c.name}</span>
                        <span className="tabular-nums">{formatMoney(c.amount, currency)}</span>
                      </div>
                      <div className="mt-1 h-1.5 w-full rounded bg-muted">
                        <div
                          className="h-1.5 rounded bg-primary"
                          style={{ width: `${(c.amount / max) * 100}%` }}
                        />
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Upcoming dues</CardTitle>
          </CardHeader>
          <CardContent>
            {upcoming.length === 0 ? (
              <p className="text-sm text-muted-foreground">Nothing due.</p>
            ) : (
              <div className="space-y-2">
                {upcoming.map((d) => (
                  <div key={d.id} className="flex items-center justify-between text-sm">
                    <div>
                      <span className="font-medium">{d.title}</span>{" "}
                      <Badge variant={d.direction === "receivable" ? "success" : "warning"}>
                        {d.direction}
                      </Badge>
                    </div>
                    <div className="text-right">
                      <div className="tabular-nums">{formatMoney(d.amount, currency)}</div>
                      <div className="text-xs text-muted-foreground">
                        {formatDate(toDate(d.dueDate))}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle className="text-base">Recent transactions</CardTitle>
        </CardHeader>
        <CardContent>
          {recent.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No transactions yet.{" "}
              <Link to="/transactions" className="underline">
                Add one
              </Link>
              .
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Note</TableHead>
                  <TableHead className="text-right">Amount</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {recent.map((t) => (
                  <TableRow key={t.id}>
                    <TableCell>{formatDate(toDate(t.date))}</TableCell>
                    <TableCell className="text-muted-foreground">{t.note ?? "—"}</TableCell>
                    <TableCell
                      className={cn(
                        "text-right tabular-nums",
                        t.totalAmount < 0 && "text-destructive",
                        t.totalAmount > 0 && "text-green-600",
                      )}
                    >
                      {formatMoney(t.totalAmount, currency)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function Metric({
  label,
  value,
  hint,
  positive,
  negative,
}: {
  label: string;
  value: string;
  hint?: string;
  positive?: boolean;
  negative?: boolean;
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-normal text-muted-foreground">{label}</CardTitle>
      </CardHeader>
      <CardContent>
        <div
          className={cn(
            "text-2xl font-semibold tabular-nums",
            positive && "text-green-600",
            negative && "text-destructive",
          )}
        >
          {value}
        </div>
        {hint && <p className="mt-1 text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  );
}
