import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/** Merge conditional class names, de-duplicating Tailwind utilities. */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
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
