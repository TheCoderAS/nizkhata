import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/** Merge conditional class names, de-duplicating Tailwind utilities. */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

/** Up-to-2-letter initials from a name or email (e.g. "Aalok Kumar" -> "AK"). */
export function initials(nameOrEmail: string): string {
  const parts = (nameOrEmail ?? "").trim().split(/[\s@.]+/).filter(Boolean);
  return ((parts[0]?.[0] ?? "?") + (parts[1]?.[0] ?? "")).toUpperCase();
}

/**
 * Deterministic, theme-friendly avatar colors derived from a seed string, so
 * each person/workspace gets a stable, distinct color. Returns inline styles
 * (a tinted background + a saturated foreground at the same hue) that read well
 * in both light and dark themes.
 */
export function avatarColor(seed: string): { backgroundColor: string; color: string } {
  let hash = 0;
  for (let i = 0; i < seed.length; i++) hash = (hash * 31 + seed.charCodeAt(i)) | 0;
  const hue = Math.abs(hash) % 360;
  return {
    backgroundColor: `hsl(${hue} 70% 50% / 0.18)`,
    color: `hsl(${hue} 65% 45%)`,
  };
}

/**
 * Format a number as workspace currency (defaults to INR / en-IN).
 * Uses accounting sign display, so negatives render in parentheses —
 * e.g. -1000 -> "(₹1,000.00)" rather than "-₹1,000.00".
 */
export function formatMoney(
  amount: number,
  currency = "INR",
  locale = "en-IN",
): string {
  // Render a true zero as an em dash — cleaner than "₹0.00" scattered across
  // tables/cards. Sub-cent epsilon so rounding noise still reads as zero.
  // (Form inputs use String(value) and CSV exports use raw numbers, so neither
  // is affected by this display-only behavior.)
  if (Math.abs(amount) < 0.005) return "—";
  return new Intl.NumberFormat(locale, {
    style: "currency",
    currency,
    currencySign: "accounting",
    maximumFractionDigits: 2,
  }).format(amount);
}

/** Format a JS Date as a short readable date. */
export function formatDate(date: Date, locale = "en-IN"): string {
  return new Intl.DateTimeFormat(locale, {
    year: "numeric",
    month: "short",
    day: "numeric",
  }).format(date);
}

/** Compact relative time, e.g. "just now", "5m ago", "3d ago", else a date. */
export function formatRelative(date: Date, locale = "en-IN"): string {
  const diffMs = Date.now() - date.getTime();
  const sec = Math.round(diffMs / 1000);
  if (sec < 45) return "just now";
  const min = Math.round(sec / 60);
  if (min < 60) return `${min}m ago`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr}h ago`;
  const day = Math.round(hr / 24);
  if (day < 7) return `${day}d ago`;
  return formatDate(date, locale);
}
