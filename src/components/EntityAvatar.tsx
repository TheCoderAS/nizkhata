// Deterministic gradient avatar for contacts / accounts / categories. Hashes the
// name to a stable hue so the same entity always gets the same colour, making
// lists scannable and colourful without storing anything. Shows initials.

import { cn } from "@/lib/utils";

function hashHue(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return Math.abs(h) % 360;
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

const SIZES = {
  sm: "h-7 w-7 text-[10px]",
  md: "h-9 w-9 text-xs",
  lg: "h-12 w-12 text-sm",
} as const;

export function EntityAvatar({
  name,
  size = "md",
  className,
}: {
  name: string;
  size?: keyof typeof SIZES;
  className?: string;
}) {
  const hue = hashHue(name || "?");
  // Two-stop gradient: the base hue into an analogous neighbour for depth.
  const from = `hsl(${hue} 70% 55%)`;
  const to = `hsl(${(hue + 40) % 360} 72% 48%)`;
  return (
    <span
      aria-hidden
      className={cn(
        "inline-flex shrink-0 select-none items-center justify-center rounded-full font-strong text-white shadow-sm ring-1 ring-black/5",
        SIZES[size],
        className,
      )}
      style={{ backgroundImage: `linear-gradient(135deg, ${from}, ${to})` }}
    >
      {initials(name)}
    </span>
  );
}
