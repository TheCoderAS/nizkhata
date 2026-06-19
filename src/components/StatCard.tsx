// Small headline-figure card: label, an animated currency amount, optional hint
// and icon. Shared by the Dashboard balances and the Dues / Debts summary rows
// so totals look consistent across the app.

import type { LucideIcon } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { CountUp } from "@/components/CountUp";
import { cn, formatMoney } from "@/lib/utils";

export type StatTone = "default" | "success" | "destructive";

const TONES: Record<StatTone, { value: string; icon: string }> = {
  default: { value: "", icon: "bg-primary/10 text-primary" },
  success: { value: "text-accent2", icon: "bg-accent2/10 text-accent2" },
  destructive: { value: "text-destructive", icon: "bg-destructive/10 text-destructive" },
};

export function StatCard({
  label,
  amount,
  currency,
  hint,
  icon: Icon,
  tone = "default",
}: {
  label: string;
  amount: number;
  currency: string;
  hint?: string;
  icon?: LucideIcon;
  tone?: StatTone;
}) {
  const t = TONES[tone];
  return (
    <Card className="elevated-hover animate-scale-in">
      <CardHeader className="flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-sm text-muted-foreground">{label}</CardTitle>
        {Icon && (
          <span className={cn("flex h-8 w-8 items-center justify-center rounded-lg", t.icon)}>
            <Icon className="h-4 w-4" />
          </span>
        )}
      </CardHeader>
      <CardContent>
        <CountUp
          value={amount}
          format={(n) => formatMoney(n, currency)}
          className={cn("block font-strong text-xl tabular-nums sm:text-2xl", t.value)}
        />
        {hint && <p className="mt-1 text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  );
}
