// Tiny trend chart for metric cards. Area sparkline (no axes/labels) so it reads
// at a glance. Colour is theme-token driven.

import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  ResponsiveContainer,
  Tooltip,
} from "recharts";
import type { TrendBucket } from "@/lib/period";

type Metric = "income" | "expense" | "net";

const STROKE: Record<Metric, string> = {
  income: "hsl(var(--success))",
  expense: "hsl(var(--destructive))",
  net: "hsl(var(--primary))",
};

export function Sparkline({
  data,
  metric,
  kind = "area",
  height = 48,
}: {
  data: TrendBucket[];
  metric: Metric;
  kind?: "area" | "bar";
  height?: number;
}) {
  if (data.length === 0) return <div style={{ height }} />;
  const color = STROKE[metric];
  const gradientId = `spark-${metric}`;

  return (
    <ResponsiveContainer width="100%" height={height}>
      {kind === "area" ? (
        <AreaChart data={data} margin={{ top: 4, bottom: 0, left: 0, right: 0 }}>
          <defs>
            <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={color} stopOpacity={0.35} />
              <stop offset="100%" stopColor={color} stopOpacity={0} />
            </linearGradient>
          </defs>
          <Tooltip
            cursor={false}
            content={<SparkTooltip metric={metric} />}
            wrapperStyle={{ outline: "none" }}
          />
          <Area
            type="monotone"
            dataKey={metric}
            stroke={color}
            strokeWidth={2}
            fill={`url(#${gradientId})`}
            isAnimationActive
            animationDuration={400}
          />
        </AreaChart>
      ) : (
        <BarChart data={data} margin={{ top: 4, bottom: 0, left: 0, right: 0 }}>
          <Tooltip
            cursor={{ fill: "hsl(var(--muted))" }}
            content={<SparkTooltip metric={metric} />}
            wrapperStyle={{ outline: "none" }}
          />
          <Bar dataKey={metric} fill={color} radius={[2, 2, 0, 0]} isAnimationActive animationDuration={400} />
        </BarChart>
      )}
    </ResponsiveContainer>
  );
}

function SparkTooltip({
  active,
  payload,
  label,
  metric,
}: {
  active?: boolean;
  payload?: Array<{ value: number }>;
  label?: string;
  metric?: string;
}) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-md border bg-popover px-2 py-1 text-xs shadow-md">
      <span className="text-muted-foreground">{label}</span>{" "}
      <span className="font-medium tabular-nums">
        {Intl.NumberFormat("en-IN", { maximumFractionDigits: 0 }).format(payload[0].value)}
      </span>
      {metric && <span className="ml-1 text-muted-foreground">{metric}</span>}
    </div>
  );
}
