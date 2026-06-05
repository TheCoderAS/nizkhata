// Dashboard (§6.2). A single period selector (week / month / year / FY / custom)
// drives income / expense / net trend cards (with sparklines), plus "in
// accounts" vs "held for others", spend-by-category, upcoming dues and recent
// transactions. Responsive: cards stack cleanly and charts scale on mobile.

import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { ArrowDownRight, ArrowUpRight, Wallet, Users } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import {
  budgetProgress,
  custodialHeld,
  dueStatusFromSettled,
  netWorthSeries,
  spendByCategoryInRange,
  toDate,
  compareTxnChrono,
} from "@/lib/derive";
import { txnsByCategory } from "@/lib/links";
import {
  PERIOD_LABELS,
  resolvePeriod,
  trendSeries,
  type DateRange,
  type PeriodKind,
} from "@/lib/period";
import { Area, AreaChart, ResponsiveContainer } from "recharts";
import { PageHeader } from "@/components/PageHeader";
import { TransactionDetailDialog } from "@/components/TransactionDetailDialog";
import { Sparkline } from "@/components/Sparkline";
import { CountUp } from "@/components/CountUp";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ErrorState, PageSkeleton } from "@/components/states";
import { cn, formatDate, formatMoney } from "@/lib/utils";

export function Dashboard() {
  const { activeWorkspace, can } = useWorkspace();
  const canViewTxns = can("transactions.view");
  const {
    accounts,
    transactions,
    dues,
    debts,
    categories,
    budgets,
    categoriesById,
    balanceOf,
    settledOf,
    loading,
    error,
  } = useData();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const fyStartMonth = activeWorkspace?.fyStartMonth ?? 4;
  const now = new Date();

  const [openTxn, setOpenTxn] = useState<(typeof transactions)[number] | null>(null);
  const [period, setPeriod] = useState<PeriodKind>("month");
  const [customStart, setCustomStart] = useState(
    new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10),
  );
  const [customEnd, setCustomEnd] = useState(now.toISOString().slice(0, 10));

  const range: DateRange = useMemo(() => {
    if (period === "custom") {
      const start = new Date(customStart);
      const end = new Date(customEnd);
      end.setDate(end.getDate() + 1); // make end inclusive
      return { start, end };
    }
    return resolvePeriod(period, now, fyStartMonth);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [period, customStart, customEnd, fyStartMonth]);

  const trend = useMemo(() => trendSeries(transactions, range), [transactions, range]);

  const totalInAccounts = useMemo(
    () => accounts.reduce((s, a) => s + balanceOf(a.id), 0),
    [accounts, balanceOf],
  );
  const held = useMemo(() => custodialHeld(debts, transactions), [debts, transactions]);

  // Net worth headline: current standing + a trailing-6-month trend, independent
  // of the period selector (net worth is a slow cumulative metric, so a fixed
  // recent window reads better than the activity window driving the cards below).
  const netWorth = useMemo(() => {
    const end = new Date(now.getFullYear(), now.getMonth() + 1, 1);
    const start = new Date(now.getFullYear(), now.getMonth() - 5, 1);
    const series = netWorthSeries(accounts, debts, transactions, start, end);
    const current = series.length ? series[series.length - 1].netWorth : 0;
    const first = series.length ? series[0].netWorth : 0;
    const delta = current - first;
    const pct = first !== 0 ? Math.round((delta / Math.abs(first)) * 100) : null;
    return { series, current, delta, pct };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [accounts, debts, transactions]);

  const topSpend = useMemo(
    () => spendByCategoryInRange(transactions, categories, range.start, range.end).slice(0, 6),
    [transactions, categories, range],
  );

  const budgetRows = useMemo(
    () => budgetProgress(budgets, transactions, categoriesById, fyStartMonth).slice(0, 4),
    [budgets, transactions, categoriesById, fyStartMonth],
  );

  const upcoming = useMemo(
    () =>
      dues
        .filter((d) => {
          const status = dueStatusFromSettled(d, settledOf(d.id));
          if (status !== "open" && status !== "partial") return false;
          // Scope to the selected period (by due date), like the other cards.
          const dd = toDate(d.dueDate);
          return dd >= range.start && dd < range.end;
        })
        .sort((a, b) => toDate(a.dueDate).getTime() - toDate(b.dueDate).getTime())
        .slice(0, 5),
    [dues, settledOf, range],
  );

  const recent = useMemo(
    () =>
      [...transactions]
        .sort((a, b) => compareTxnChrono(b, a)) // newest first
        .slice(0, 6),
    [transactions],
  );

  if (loading) return <PageSkeleton />;
  if (error) return <ErrorState message={error} />;

  return (
    <div className="space-y-4 sm:space-y-6">
      <PageHeader
        title="Dashboard"
        actions={
          <Select value={period} onValueChange={(v) => setPeriod(v as PeriodKind)}>
            <SelectTrigger className="w-[150px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {(["week", "month", "year", "fy", "custom"] as PeriodKind[]).map((p) => (
                <SelectItem key={p} value={p}>
                  {PERIOD_LABELS[p]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        }
      />

      {period === "custom" && (
        <div className="flex flex-wrap items-end gap-3">
          <div className="space-y-1">
            <label className="text-xs text-muted-foreground">From</label>
            <Input type="date" value={customStart} onChange={(e) => setCustomStart(e.target.value)} />
          </div>
          <div className="space-y-1">
            <label className="text-xs text-muted-foreground">To</label>
            <Input type="date" value={customEnd} onChange={(e) => setCustomEnd(e.target.value)} />
          </div>
        </div>
      )}

      {/* net-worth hero */}
      <div className="brand-gradient relative overflow-hidden rounded-2xl p-5 text-white shadow-lg sm:p-6 animate-scale-in">
        {/* soft sheen */}
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(40rem_20rem_at_120%_-20%,rgba(255,255,255,0.25),transparent_60%)]" />
        <div className="relative flex items-end justify-between gap-4">
          <div className="min-w-0">
            <p className="text-sm font-medium text-white/80">Net worth</p>
            <CountUp
              value={netWorth.current}
              format={(n) => formatMoney(n, currency)}
              className="mt-1 block font-strong text-3xl tabular-nums tracking-tight sm:text-4xl"
            />
            {netWorth.delta !== 0 && (
              <p className="mt-2 flex items-center gap-1.5 text-sm text-white/90">
                <span
                  className={cn(
                    "inline-flex items-center gap-1 rounded-full bg-white/15 px-2 py-0.5 text-xs font-medium tabular-nums backdrop-blur",
                  )}
                >
                  {netWorth.delta > 0 ? <ArrowUpRight className="h-3.5 w-3.5" /> : <ArrowDownRight className="h-3.5 w-3.5" />}
                  {netWorth.pct != null ? `${Math.abs(netWorth.pct)}%` : formatMoney(Math.abs(netWorth.delta), currency)}
                </span>
                <span className="truncate text-white/70">
                  {netWorth.delta > 0 ? "+" : "−"}
                  {formatMoney(Math.abs(netWorth.delta), currency)} · last 6 months
                </span>
              </p>
            )}
          </div>
          {netWorth.series.length > 1 && (
            <div className="hidden h-16 w-40 shrink-0 sm:block" aria-hidden>
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={netWorth.series} margin={{ top: 4, bottom: 0, left: 0, right: 0 }}>
                  <defs>
                    <linearGradient id="hero-nw" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="white" stopOpacity={0.5} />
                      <stop offset="100%" stopColor="white" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <Area
                    type="monotone"
                    dataKey="netWorth"
                    stroke="white"
                    strokeWidth={2}
                    fill="url(#hero-nw)"
                    isAnimationActive
                    animationDuration={600}
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          )}
        </div>
      </div>

      {/* trend cards */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3 sm:gap-4">
        <TrendCard
          label="Income"
          amount={trend.totals.income}
          currency={currency}
          metric="income"
          data={trend.buckets}
          icon={ArrowUpRight}
          tone="success"
        />
        <TrendCard
          label="Expense"
          amount={trend.totals.expense}
          currency={currency}
          metric="expense"
          data={trend.buckets}
          icon={ArrowDownRight}
          tone="destructive"
        />
        <TrendCard
          label="Net"
          amount={trend.totals.net}
          currency={currency}
          metric="net"
          data={trend.buckets}
          kind="bar"
          tone={trend.totals.net >= 0 ? "success" : "destructive"}
        />
      </div>

      {/* balances */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 sm:gap-4">
        <StatCard
          label="Total in accounts"
          amount={totalInAccounts}
          currency={currency}
          icon={Wallet}
        />
        <StatCard
          label="Held for others (Custodial)"
          amount={held}
          currency={currency}
          icon={Users}
        />
      </div>

      {/* breakdowns */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base">
              Spend by category · {PERIOD_LABELS[period]}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {topSpend.length === 0 ? (
              <p className="text-sm text-muted-foreground">No spend recorded.</p>
            ) : (
              <div className="space-y-2.5">
                {topSpend.map((c) => {
                  const max = topSpend[0].amount || 1;
                  const Row = (
                    <>
                      <div className="flex justify-between text-sm">
                        <span className="truncate pr-2">{c.name}</span>
                        <span className="tabular-nums">{formatMoney(c.amount, currency)}</span>
                      </div>
                      <div className="mt-1 h-2 w-full overflow-hidden rounded-full bg-muted">
                        <div
                          className="h-2 rounded-full bg-primary transition-all"
                          style={{ width: `${(c.amount / max) * 100}%` }}
                        />
                      </div>
                    </>
                  );
                  return canViewTxns ? (
                    <Link
                      key={c.categoryId}
                      to={txnsByCategory(c.categoryId)}
                      className="block rounded-md p-1 -m-1 transition-colors hover:bg-muted/50"
                    >
                      {Row}
                    </Link>
                  ) : (
                    <div key={c.categoryId}>{Row}</div>
                  );
                })}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base">Upcoming dues</CardTitle>
          </CardHeader>
          <CardContent>
            {upcoming.length === 0 ? (
              <p className="text-sm text-muted-foreground">Nothing due.</p>
            ) : (
              <div className="divide-y">
                {upcoming.map((d) => (
                  <div key={d.id} className="flex items-center justify-between gap-2 py-2 first:pt-0 last:pb-0 text-sm">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="truncate font-medium">{d.title}</span>
                        <Badge variant={d.direction === "receivable" ? "success" : "warning"}>
                          {d.direction}
                        </Badge>
                      </div>
                      <div className="text-xs text-muted-foreground">
                        {formatDate(toDate(d.dueDate))}
                      </div>
                    </div>
                    <span className="shrink-0 tabular-nums">{formatMoney(d.amount, currency)}</span>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {budgetRows.length > 0 && (
        <Card>
          <CardHeader className="pb-3">
            <CardTitle className="text-base">Budgets</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {budgetRows.map((p) => {
                const pct = Math.min(100, Math.round(p.ratio * 100));
                return (
                  <div key={p.budgetId}>
                    <div className="flex justify-between gap-2 text-sm">
                      <span className="flex min-w-0 items-center gap-2">
                        <span className="truncate">{p.categoryName}</span>
                        <span className="shrink-0 rounded bg-muted px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-muted-foreground">
                          {p.periodLabel}
                        </span>
                      </span>
                      <span
                        className={cn(
                          "shrink-0 tabular-nums",
                          p.over ? "text-destructive" : "text-muted-foreground",
                        )}
                      >
                        {formatMoney(p.spent, currency)} / {formatMoney(p.limit, currency)}
                      </span>
                    </div>
                    <div className="mt-1 h-2 w-full overflow-hidden rounded-full bg-muted">
                      <div
                        className={cn(
                          "h-2 rounded-full transition-all",
                          p.over ? "bg-destructive" : p.ratio > 0.8 ? "bg-warning" : "bg-primary",
                        )}
                        style={{ width: `${pct}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </CardContent>
        </Card>
      )}

      {/* recent */}
      <Card>
        <CardHeader className="pb-3">
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
            <div className="divide-y">
              {recent.map((t) => (
                <button
                  key={t.id}
                  onClick={() => setOpenTxn(t)}
                  className="flex w-full items-center justify-between gap-3 py-2 text-left first:pt-0 last:pb-0 hover:bg-accent/50"
                >
                  <div className="min-w-0">
                    <div className="truncate text-sm font-medium">{t.note ?? "Transaction"}</div>
                    <div className="text-xs text-muted-foreground">{formatDate(toDate(t.date))}</div>
                  </div>
                  <span
                    className={cn(
                      "shrink-0 text-sm tabular-nums",
                      t.totalAmount < 0 && "text-destructive",
                      t.totalAmount > 0 && "text-green-600",
                    )}
                  >
                    {formatMoney(t.totalAmount, currency)}
                  </span>
                </button>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {openTxn && (
        <TransactionDetailDialog txn={openTxn} onClose={() => setOpenTxn(null)} />
      )}
    </div>
  );
}

function TrendCard({
  label,
  amount,
  currency,
  metric,
  data,
  icon: Icon,
  kind = "area",
  tone,
}: {
  label: string;
  amount: number;
  currency: string;
  metric: "income" | "expense" | "net";
  data: import("@/lib/period").TrendBucket[];
  icon?: typeof Wallet;
  kind?: "area" | "bar";
  tone: "success" | "destructive";
}) {
  return (
    <Card className="elevated-hover animate-scale-in overflow-hidden">
      <CardHeader className="flex-row items-center justify-between space-y-0 pb-1">
        <CardTitle className="text-sm text-muted-foreground">{label}</CardTitle>
        {Icon && (
          <span
            className={cn(
              "flex h-8 w-8 items-center justify-center rounded-lg",
              tone === "success"
                ? "bg-accent2/10 text-accent2"
                : "bg-destructive/10 text-destructive",
            )}
          >
            <Icon className="h-4 w-4" />
          </span>
        )}
      </CardHeader>
      <CardContent className="pb-0">
        <CountUp
          value={amount}
          format={(n) => formatMoney(n, currency)}
          className={cn(
            "block font-strong text-xl tabular-nums sm:text-2xl",
            tone === "success" ? "text-accent2" : "text-destructive",
          )}
        />
        <div className="-mx-2 mt-2">
          <Sparkline data={data} metric={metric} kind={kind} />
        </div>
      </CardContent>
    </Card>
  );
}

function StatCard({
  label,
  amount,
  currency,
  hint,
  icon: Icon,
}: {
  label: string;
  amount: number;
  currency: string;
  hint?: string;
  icon?: typeof Wallet;
}) {
  return (
    <Card className="elevated-hover animate-scale-in">
      <CardHeader className="flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm text-muted-foreground">{label}</CardTitle>
        {Icon && (
          <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <Icon className="h-4 w-4" />
          </span>
        )}
      </CardHeader>
      <CardContent>
        <CountUp
          value={amount}
          format={(n) => formatMoney(n, currency)}
          className="block font-strong text-xl tabular-nums sm:text-2xl"
        />
        {hint && <p className="mt-1 text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  );
}
