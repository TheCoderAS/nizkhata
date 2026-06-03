// Full-size income-vs-expense trend chart for the Reports "Insights" tab.
// Grouped bars per bucket (day or month, decided by trendSeries) with axes, a
// legend and a themed tooltip. Colour is theme-token driven.

import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { TrendBucket } from "@/lib/period";
import { formatMoney } from "@/lib/utils";

export function TrendChart({
  data,
  currency,
  height = 280,
}: {
  data: TrendBucket[];
  currency: string;
  height?: number;
}) {
  if (data.length === 0) {
    return (
      <div className="flex items-center justify-center text-sm text-muted-foreground" style={{ height }}>
        No data for this period.
      </div>
    );
  }

  const compact = (n: number) =>
    Intl.NumberFormat("en-IN", { notation: "compact", maximumFractionDigits: 1 }).format(n);

  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
        <XAxis
          dataKey="label"
          tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }}
          tickLine={false}
          axisLine={false}
          interval="preserveStartEnd"
        />
        <YAxis
          tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }}
          tickLine={false}
          axisLine={false}
          width={48}
          tickFormatter={compact}
        />
        <Tooltip
          cursor={{ fill: "hsl(var(--muted) / 0.5)" }}
          wrapperStyle={{ outline: "none" }}
          content={<ChartTooltip currency={currency} />}
        />
        <Legend
          iconType="circle"
          wrapperStyle={{ fontSize: 12, paddingTop: 8 }}
        />
        <Bar name="Income" dataKey="income" fill="hsl(var(--success))" radius={[3, 3, 0, 0]} />
        <Bar name="Expense" dataKey="expense" fill="hsl(var(--destructive))" radius={[3, 3, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}

function ChartTooltip({
  active,
  payload,
  label,
  currency,
}: {
  active?: boolean;
  payload?: Array<{ name: string; value: number; color: string }>;
  label?: string;
  currency?: string;
}) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-md border bg-popover px-2.5 py-1.5 text-xs shadow-md">
      <p className="mb-1 font-medium">{label}</p>
      {payload.map((p) => (
        <p key={p.name} className="flex items-center gap-1.5">
          <span className="h-2 w-2 rounded-full" style={{ background: p.color }} />
          <span className="text-muted-foreground">{p.name}</span>
          <span className="ml-auto tabular-nums">{formatMoney(p.value, currency)}</span>
        </p>
      ))}
    </div>
  );
}
