// Brand logo. `mark` renders just the icon (open book + monogram + arrow);
// `full` renders the icon plus the "NizKhata" wordmark. Used in the auth
// screens, app header and sidebar so the brand stays consistent everywhere.

import logoUrl from "@/assets/logo.png";
import { cn } from "@/lib/utils";

const SIZES = {
  sm: "h-7 w-7",
  md: "h-9 w-9",
  lg: "h-12 w-12",
  xl: "h-16 w-16",
} as const;

export function LogoMark({
  size = "md",
  className,
}: {
  size?: keyof typeof SIZES;
  className?: string;
}) {
  return (
    <img
      src={logoUrl}
      alt="NizKhata"
      className={cn("shrink-0 rounded-xl object-cover", SIZES[size], className)}
    />
  );
}

export function Logo({
  size = "md",
  className,
  wordmarkClassName,
}: {
  size?: keyof typeof SIZES;
  className?: string;
  /** Overrides the default brand-gradient wordmark (e.g. a plain footer mark). */
  wordmarkClassName?: string;
}) {
  return (
    <span className={cn("inline-flex items-center gap-2", className)}>
      <LogoMark size={size} />
      <span
        className={cn(
          "font-semibold tracking-tight",
          // Gradient wordmark by default; callers can override (e.g. footer).
          wordmarkClassName ?? "brand-gradient-text",
        )}
      >
        NizKhata
      </span>
    </span>
  );
}
