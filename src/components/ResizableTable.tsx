// Drop-in replacement for the <Table> primitive that makes columns
// drag-resizable. Replace `<Table>…</Table>` with `<ResizableTable prefs={cols}>
// …</ResizableTable>` (same scroll wrapper + <table> markup) and each resizable
// header gets a drag handle automatically via SortableHead.
//
// Design: the table only switches to `table-layout: fixed` once the user has
// dragged at least one column (prefs.hasCustomWidths). On the first drag we seed
// every visible column's width from its current rendered size, so there's no
// visual jump — the table keeps exactly what it looked like, then becomes
// adjustable. Widths persist via useColumnPrefs (localStorage).

import {
  createContext,
  useCallback,
  useContext,
  useRef,
  type ReactNode,
} from "react";
import { cn } from "@/lib/utils";
import { TableHead } from "@/components/ui/table";
import type { ColumnPrefs } from "@/lib/useColumnPrefs";

interface Ctx {
  widthOf: (key: string) => number | undefined;
  beginResize: (key: string, startX: number, headerEl: HTMLElement) => void;
}

const ColumnWidthContext = createContext<Ctx | null>(null);

export function ResizableTable<K extends string>({
  prefs,
  children,
  className,
}: {
  prefs: ColumnPrefs<K>;
  children: ReactNode;
  className?: string;
}) {
  const tableRef = useRef<HTMLTableElement>(null);

  // On the first drag, capture the current rendered width of every header cell
  // so switching to fixed layout doesn't reflow the table.
  const seedFromDom = useCallback(() => {
    if (prefs.hasCustomWidths) return;
    const headers = tableRef.current?.querySelectorAll<HTMLElement>("thead th[data-col-key]");
    headers?.forEach((th) => {
      const key = th.dataset.colKey;
      if (key) prefs.setWidth(key as K, th.getBoundingClientRect().width);
    });
  }, [prefs]);

  const beginResize = useCallback(
    (key: string, startX: number, headerEl: HTMLElement) => {
      seedFromDom();
      const startWidth = headerEl.getBoundingClientRect().width;
      const onMove = (e: PointerEvent) =>
        prefs.setWidth(key as K, startWidth + (e.clientX - startX));
      const onUp = () => {
        window.removeEventListener("pointermove", onMove);
        window.removeEventListener("pointerup", onUp);
        document.body.style.userSelect = "";
        document.body.style.cursor = "";
      };
      document.body.style.userSelect = "none";
      document.body.style.cursor = "col-resize";
      window.addEventListener("pointermove", onMove);
      window.addEventListener("pointerup", onUp);
    },
    [prefs, seedFromDom],
  );

  const ctx: Ctx = { widthOf: (k) => prefs.widthOf(k as K), beginResize };

  return (
    <ColumnWidthContext.Provider value={ctx}>
      <div className="relative w-full overflow-auto">
        <table
          ref={tableRef}
          className={cn(
            "w-full caption-bottom text-sm",
            prefs.hasCustomWidths && "table-fixed",
            className,
          )}
        >
          {children}
        </table>
      </div>
    </ColumnWidthContext.Provider>
  );
}

export function useColumnWidth() {
  return useContext(ColumnWidthContext);
}

/**
 * A plain (non-sortable) <TableHead> that is drag-resizable inside a
 * <ResizableTable>. Use for tables that don't use SortableHead (e.g. the
 * account ledger). `colKey` keys the persisted width.
 */
export function ResizableHead({
  colKey,
  className,
  children,
}: {
  colKey: string;
  className?: string;
  children: ReactNode;
}) {
  const ctx = useColumnWidth();
  const width = ctx?.widthOf(colKey);
  return (
    <TableHead
      className={cn("relative", className)}
      data-col-key={colKey}
      style={width ? { width, maxWidth: width } : undefined}
    >
      <span className="block max-w-full truncate">{children}</span>
      <ColResizer colKey={colKey} />
    </TableHead>
  );
}

/** A grab handle on the right edge of a header cell that resizes its column. */
export function ColResizer({ colKey }: { colKey: string }) {
  const ctx = useColumnWidth();
  if (!ctx) return null; // not inside a ResizableTable — render nothing
  return (
    <span
      role="separator"
      aria-orientation="vertical"
      aria-label="Resize column"
      onPointerDown={(e) => {
        e.preventDefault();
        e.stopPropagation();
        const th = (e.currentTarget as HTMLElement).closest("th");
        if (th) ctx.beginResize(colKey, e.clientX, th);
      }}
      onClick={(e) => e.stopPropagation()}
      className="absolute inset-y-0 right-0 z-10 w-2 cursor-col-resize touch-none select-none before:absolute before:inset-y-1.5 before:right-0.5 before:w-px before:bg-border hover:before:w-0.5 hover:before:bg-primary"
    />
  );
}
