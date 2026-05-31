// Persisted per-table column visibility + widths. Each table declares its
// columns with a `defaultVisible` flag (keep the default set minimal — max ~4).
// The user's show/hide choices and any drag-resized column widths are saved to
// localStorage under the table key and restored on refresh.

import { useCallback, useEffect, useMemo, useState } from "react";

export interface ColumnDef<K extends string> {
  key: K;
  label: string;
  /** part of the minimal default view (max ~4 recommended) */
  defaultVisible: boolean;
  /** cannot be hidden (e.g. the primary name column + the actions column) */
  locked?: boolean;
}

const STORAGE_PREFIX = "table-cols:";
const WIDTH_PREFIX = "table-colw:";

// Clamp drag-resized widths to something usable.
export const MIN_COL_WIDTH = 64;
export const MAX_COL_WIDTH = 720;

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

function loadWidths(tableKey: string): Record<string, number> {
  try {
    const raw = localStorage.getItem(WIDTH_PREFIX + tableKey);
    return raw ? (JSON.parse(raw) as Record<string, number>) : {};
  } catch {
    return {};
  }
}

function saveWidths(tableKey: string, value: Record<string, number>) {
  try {
    localStorage.setItem(WIDTH_PREFIX + tableKey, JSON.stringify(value));
  } catch {
    /* storage unavailable */
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

  // Per-column widths (px). Empty until the user drags a column; once any width
  // is set the table switches to fixed layout so the widths take effect.
  const [widths, setWidths] = useState<Record<string, number>>(() => loadWidths(tableKey));

  useEffect(() => {
    save(tableKey, visible);
  }, [tableKey, visible]);

  useEffect(() => {
    saveWidths(tableKey, widths);
  }, [tableKey, widths]);

  const isVisible = useCallback((key: K) => visible[key] !== false, [visible]);

  const toggle = useCallback(
    (key: K) => {
      const col = columns.find((c) => c.key === key);
      if (col?.locked) return;
      setVisible((prev) => ({ ...prev, [key]: !prev[key] }));
    },
    [columns],
  );

  const widthOf = useCallback((key: K): number | undefined => widths[key], [widths]);

  const setWidth = useCallback((key: K, px: number) => {
    const clamped = Math.max(MIN_COL_WIDTH, Math.min(MAX_COL_WIDTH, Math.round(px)));
    setWidths((prev) => ({ ...prev, [key]: clamped }));
  }, []);

  // True once any column has been manually sized — drives table-layout: fixed.
  const hasCustomWidths = Object.keys(widths).length > 0;

  const resetWidths = useCallback(() => setWidths({}), []);

  const reset = useCallback(() => {
    setVisible(defaults);
    setWidths({});
  }, [defaults]);

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
