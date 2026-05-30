// Financial-year helpers. FY label is derived from a date + workspace
// fyStartMonth (§2). For fyStartMonth = 4 (April), a date in 2025-05 is FY
// "2025-26"; a date in 2025-02 is FY "2024-25".

/**
 * Returns the FY label (e.g. "2025-26") for a date given the workspace's
 * fiscal-year start month (1-12).
 *
 * If fyStartMonth is 1 (January), the label is just the single year "2025".
 */
export function financialYearOf(date: Date, fyStartMonth: number): string {
  const month = date.getMonth() + 1; // 1-12
  const year = date.getFullYear();

  // Year in which the current FY started.
  const startYear = month >= fyStartMonth ? year : year - 1;

  if (fyStartMonth === 1) return String(startYear);

  const endYearShort = String((startYear + 1) % 100).padStart(2, "0");
  return `${startYear}-${endYearShort}`;
}

/** Inclusive [start, end) date range of the FY that `date` falls into. */
export function financialYearRange(
  date: Date,
  fyStartMonth: number,
): { start: Date; end: Date } {
  const month = date.getMonth() + 1;
  const year = date.getFullYear();
  const startYear = month >= fyStartMonth ? year : year - 1;
  const start = new Date(startYear, fyStartMonth - 1, 1, 0, 0, 0, 0);
  const end = new Date(startYear + 1, fyStartMonth - 1, 1, 0, 0, 0, 0);
  return { start, end };
}
