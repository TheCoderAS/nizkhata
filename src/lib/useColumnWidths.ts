// Persisted, drag-resizable column widths for a table — independent of column
// visibility. useColumnPrefs builds on this; tables that don't need a
// show/hide ColumnsMenu (e.g. Members, Reports, the detail panes) can use this
// directly to get resizable columns. Widths are keyed per table and stored in
// localStorage.

import { useCallback, useEffect, useState } from "react";

const WIDTH_PREFIX = "table-colw:";

// Clamp drag-resized widths to something usable.
export const MIN_COL_WIDTH = 64;
export const MAX_COL_WIDTH = 720;

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

// The minimal contract <ResizableTable> needs. Both useColumnWidths and
// useColumnPrefs satisfy it.
export interface ColumnWidths {
  widthOf: (key: string) => number | undefined;
  setWidth: (key: string, px: number) => void;
  /** true once any column has been manually sized — drives table-layout: fixed */
  hasCustomWidths: boolean;
  resetWidths: () => void;
}

export function useColumnWidths(tableKey: string): ColumnWidths {
  const [widths, setWidths] = useState<Record<string, number>>(() => loadWidths(tableKey));

  useEffect(() => {
    saveWidths(tableKey, widths);
  }, [tableKey, widths]);

  const widthOf = useCallback((key: string): number | undefined => widths[key], [widths]);

  const setWidth = useCallback((key: string, px: number) => {
    const clamped = Math.max(MIN_COL_WIDTH, Math.min(MAX_COL_WIDTH, Math.round(px)));
    setWidths((prev) => ({ ...prev, [key]: clamped }));
  }, []);

  const resetWidths = useCallback(() => setWidths({}), []);

  return {
    widthOf,
    setWidth,
    hasCustomWidths: Object.keys(widths).length > 0,
    resetWidths,
  };
}
