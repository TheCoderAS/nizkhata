// Persisted per-table column visibility. Each table declares its columns with a
// `defaultVisible` flag (keep the default set minimal — max ~4). The user's
// show/hide choices are saved to localStorage under the table key and restored
// on refresh.

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

  const reset = useCallback(() => setVisible(defaults), [defaults]);

  return { columns, isVisible, toggle, reset };
}
