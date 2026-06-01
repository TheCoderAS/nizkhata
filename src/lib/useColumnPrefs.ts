// Persisted per-table column visibility + widths. Each table declares its
// columns with a `defaultVisible` flag (keep the default set minimal — max ~4).
// The user's show/hide choices and any drag-resized column widths are saved to
// localStorage under the table key and restored on refresh.

import { useCallback, useEffect, useMemo, useState } from "react";
import { useColumnWidths, MIN_COL_WIDTH, MAX_COL_WIDTH } from "./useColumnWidths";

export interface ColumnDef<K extends string> {
  key: K;
  label: string;
  /** part of the minimal default view (max ~4 recommended) */
  defaultVisible: boolean;
  /** cannot be hidden (e.g. the primary name column + the actions column) */
  locked?: boolean;
}

const STORAGE_PREFIX = "table-cols:";

// Re-exported for back-compat (the clamp bounds live in useColumnWidths now).
export { MIN_COL_WIDTH, MAX_COL_WIDTH };

function load(tableKey: string): Record<string, boolean> | null {
  try {
    const raw = localStorage.getItem(STORAGE_PREFIX + tableKey);
    return raw ? (JSON.parse(raw) as Record<string, boolean>) : null;
  } catch {
    return null;
  }
}

function save(tableKey: string, value: Record<string, boolean>) {
  try {
    localStorage.setItem(STORAGE_PREFIX + tableKey, JSON.stringify(value));
  } catch {
    /* storage unavailable — keep in-memory only */
  }
}

export function useColumnPrefs<K extends string>(
  tableKey: string,
  columns: ColumnDef<K>[],
) {
  const defaults = useMemo(() => {
    const map = {} as Record<K, boolean>;
    for (const c of columns) map[c.key] = c.locked ? true : c.defaultVisible;
    return map;
  }, [columns]);

  const [visible, setVisible] = useState<Record<K, boolean>>(() => {
    const stored = load(tableKey);
    if (!stored) return defaults;
    // merge: respect stored choices but honour locked + any newly added columns
    const merged = { ...defaults };
    for (const c of columns) {
      if (c.locked) merged[c.key] = true;
      else if (c.key in stored) merged[c.key] = stored[c.key];
    }
    return merged;
  });

  // Per-column widths are delegated to the shared width hook (same localStorage
  // key shape), so visibility and width concerns stay separate.
  const { widthOf, setWidth, hasCustomWidths, resetWidths } = useColumnWidths(tableKey);

  useEffect(() => {
    save(tableKey, visible);
  }, [tableKey, visible]);

  const isVisible = useCallback((key: K) => visible[key] !== false, [visible]);

  const toggle = useCallback(
    (key: K) => {
      const col = columns.find((c) => c.key === key);
      if (col?.locked) return;
      setVisible((prev) => ({ ...prev, [key]: !prev[key] }));
    },
    [columns],
  );

  const reset = useCallback(() => {
    setVisible(defaults);
    resetWidths();
  }, [defaults, resetWidths]);

  return {
    columns,
    isVisible,
    toggle,
    reset,
    widthOf,
    setWidth,
    hasCustomWidths,
    resetWidths,
  };
}

export type ColumnPrefs<K extends string> = ReturnType<typeof useColumnPrefs<K>>;
