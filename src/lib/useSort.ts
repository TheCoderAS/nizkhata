// Generic client-side sorting hook for table data. Returns the sorted array and
// the controls a sortable header needs. Stable: equal keys preserve input order.

import { useMemo, useState } from "react";

export type SortDirection = "asc" | "desc";

export interface SortState<K extends string> {
  key: K | null;
  direction: SortDirection;
}

export type SortAccessor<T> = (row: T) => string | number | Date | null | undefined;

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
        const va = normalize(accessor(a.row));
        const vb = normalize(accessor(b.row));
        if (va < vb) return -1 * dir;
        if (va > vb) return 1 * dir;
        return a.index - b.index;
      })
      .map((d) => d.row);
  }, [rows, sort, accessors]);

  return { sorted, sort, toggle };
}

function normalize(v: string | number | Date | null | undefined): number | string {
  if (v == null) return ""; // nulls sort first ascending
  if (v instanceof Date) return v.getTime();
  if (typeof v === "string") return v.toLowerCase();
  return v;
}
