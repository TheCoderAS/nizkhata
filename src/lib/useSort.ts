// Generic client-side sorting hook for table data. Returns the sorted array and
// the controls a sortable header needs. Stable: equal keys preserve input order.

import { useMemo, useState } from "react";

export type SortDirection = "asc" | "desc";

export interface SortState<K extends string> {
  key: K | null;
  direction: SortDirection;
}

export type SortPrimitive = string | number | Date | null | undefined;
// An accessor may return a single value or a tuple for multi-level (tie-broken)
// comparison — e.g. [date, createdAt] sorts by date, then by full timestamp.
export type SortAccessor<T> = (row: T) => SortPrimitive | SortPrimitive[];

/**
 * @param rows   the data to sort
 * @param accessors  map of sort key -> value accessor for that column
 * @param initial    optional initial sort
 */
export function useSort<T, K extends string>(
  rows: T[],
  accessors: Record<K, SortAccessor<T>>,
  // NoInfer so K is driven by `accessors` (the full key set), not the single
  // key in `initial`.
  initial?: SortState<NoInfer<K>>,
) {
  const [sort, setSort] = useState<SortState<K>>(
    initial ?? { key: null, direction: "asc" },
  );

  function toggle(key: K) {
    setSort((prev) => {
      if (prev.key !== key) return { key, direction: "asc" };
      if (prev.direction === "asc") return { key, direction: "desc" };
      return { key: null, direction: "asc" }; // third click clears
    });
  }

  const sorted = useMemo(() => {
    if (!sort.key) return rows;
    const accessor = accessors[sort.key];
    const dir = sort.direction === "asc" ? 1 : -1;
    // decorate-sort-undecorate to keep it stable
    return rows
      .map((row, index) => ({ row, index }))
      .sort((a, b) => {
        const c = compareKeys(accessor(a.row), accessor(b.row));
        if (c !== 0) return c * dir;
        return a.index - b.index;
      })
      .map((d) => d.row);
  }, [rows, sort, accessors]);

  return { sorted, sort, toggle };
}

function normalize(v: SortPrimitive): number | string {
  if (v == null) return ""; // nulls sort first ascending
  if (v instanceof Date) return v.getTime();
  if (typeof v === "string") return v.toLowerCase();
  return v;
}

/** Compare single values or tuples lexicographically (level by level). */
function compareKeys(
  a: SortPrimitive | SortPrimitive[],
  b: SortPrimitive | SortPrimitive[],
): number {
  const av = Array.isArray(a) ? a : [a];
  const bv = Array.isArray(b) ? b : [b];
  const len = Math.max(av.length, bv.length);
  for (let i = 0; i < len; i++) {
    const na = normalize(av[i]);
    const nb = normalize(bv[i]);
    if (na < nb) return -1;
    if (na > nb) return 1;
  }
  return 0;
}
