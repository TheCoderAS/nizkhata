// Charts for the Reports "Insights" tab: net-worth line, stacked category trend,
// and a donut for category/contact splits. All theme-token driven, sharing a
// small palette and a money tooltip. Kept together since they're only used here.

import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { formatMoney } from "@/lib/utils";
import type { NetWorthPoint, CategoryTrend } from "@/lib/derive";

// Categorical palette for stacked/donut series. Cycles if exceeded.
export const SERIES_COLORS = [
  "hsl(217 91% 60%)",
  "hsl(160 84% 39%)",
  "hsl(35 92% 55%)",
  "hsl(280 65% 60%)",
  "hsl(0 72% 58%)",
  "hsl(190 80% 45%)",
];

const compact = (n: number) =>
  Intl.NumberFormat("en-IN", { notation: "compact", maximumFractionDigits: 1 }).format(n);

const axisTick = { fontSize: 11, fill: "hsl(var(--muted-foreground))" } as const;

function MoneyTooltip({
  active,
  payload,
  label,
  currency,
  total,
}: {
  active?: boolean;
  payload?: Array<{ name: string; value: number; color: string }>;
  label?: string;
  currency?: string;
  total?: boolean;
}) {
  if (!active || !payload?.length) return null;
  const sum = payload.reduce((s, p) => s + (p.value ?? 0), 0);
  return (
    <div className="rounded-md border bg-popover px-2.5 py-1.5 text-xs shadow-md">
      {label != null && <p className="mb-1 font-medium">{label}</p>}
      {payload.map((p) => (
        <p key={p.name} className="flex items-center gap-1.5">
          <span className="h-2 w-2 rounded-full" style={{ background: p.color }} />
          <span className="text-muted-foreground">{p.name}</span>
          <span className="ml-auto pl-3 tabular-nums">{formatMoney(p.value, currency)}</span>
        </p>
      ))}
      {total && payload.length > 1 && (
        <p className="mt-1 flex items-center gap-1.5 border-t pt-1 font-medium">
          <span className="text-muted-foreground">Total</span>
          <span className="ml-auto pl-3 tabular-nums">{formatMoney(sum, currency)}</span>
        </p>
      )}
    </div>
  );
}

export function NetWorthChart({
  data,
  currency,
  height = 260,
}: {
  data: NetWorthPoint[];
  currency: string;
  height?: number;
}) {
  if (data.length === 0)
    return <EmptyChart height={height} />;
  return (
    <ResponsiveContainer width="100%" height={height}>
      <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
        <defs>
          <linearGradient id="nw-fill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity={0.3} />
            <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
        <XAxis dataKey="label" tick={axisTick} tickLine={false} axisLine={false} interval="preserveStartEnd" />
        <YAxis tick={axisTick} tickLine={false} axisLine={false} width={48} tickFormatter={compact} />
        <Tooltip cursor={{ stroke: "hsl(var(--border))" }} wrapperStyle={{ outline: "none" }}
          content={<MoneyTooltip currency={currency} />} />
        <Area
          name="Net worth"
          type="monotone"
          dataKey="netWorth"
          stroke="hsl(var(--primary))"
          strokeWidth={2}
          fill="url(#nw-fill)"
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}

export function CategoryTrendChart({
  trend,
  currency,
  height = 280,
}: {
  trend: CategoryTrend;
  currency: string;
  height?: number;
}) {
  if (trend.keys.length === 0) return <EmptyChart height={height} />;
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={trend.buckets} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
        <XAxis dataKey="label" tick={axisTick} tickLine={false} axisLine={false} interval="preserveStartEnd" />
        <YAxis tick={axisTick} tickLine={false} axisLine={false} width={48} tickFormatter={compact} />
        <Tooltip cursor={{ fill: "hsl(var(--muted) / 0.5)" }} wrapperStyle={{ outline: "none" }}
          content={<MoneyTooltip currency={currency} total />} />
        <Legend iconType="circle" wrapperStyle={{ fontSize: 12, paddingTop: 8 }} />
        {trend.keys.map((k, i) => (
          <Bar
            key={k}
            dataKey={k}
            stackId="spend"
            fill={SERIES_COLORS[i % SERIES_COLORS.length]}
            radius={i === trend.keys.length - 1 ? [3, 3, 0, 0] : undefined}
          />
        ))}
      </BarChart>
    </ResponsiveContainer>
  );
}

export function DonutChart({
  data,
  currency,
  centerLabel = "Total",
  height = 240,
}: {
  data: Array<{ name: string; value: number }>;
  currency: string;
  // Caption under the centered total inside the donut hole.
  centerLabel?: string;
  height?: number;
}) {
  if (data.length === 0) return <EmptyChart height={height} />;
  const total = data.reduce((s, d) => s + d.value, 0);
  return (
    <div className="relative" style={{ height }}>
      <ResponsiveContainer width="100%" height="100%">
        <PieChart>
          <Tooltip wrapperStyle={{ outline: "none" }} content={<MoneyTooltip currency={currency} />} />
          <Legend iconType="circle" wrapperStyle={{ fontSize: 12 }} />
          <Pie
            data={data}
            dataKey="value"
            nameKey="name"
            innerRadius="58%"
            outerRadius="82%"
            paddingAngle={1}
            strokeWidth={0}
          >
            {data.map((_, i) => (
              <Cell key={i} fill={SERIES_COLORS[i % SERIES_COLORS.length]} />
            ))}
          </Pie>
        </PieChart>
      </ResponsiveContainer>
      {/* Center total overlay — sits over the donut hole. Legend takes the
          bottom strip, so nudge the label up to stay centered on the ring. */}
      <div className="pointer-events-none absolute inset-0 bottom-7 flex flex-col items-center justify-center">
        <span className="text-[11px] text-muted-foreground">{centerLabel}</span>
        <span className="font-strong text-lg tabular-nums">{formatMoney(total, currency)}</span>
      </div>
    </div>
  );
}

function EmptyChart({ height }: { height: number }) {
  return (
    <div className="flex items-center justify-center text-sm text-muted-foreground" style={{ height }}>
      No data for this period.
    </div>
  );
}
