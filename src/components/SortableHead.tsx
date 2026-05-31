// A <TableHead> that doubles as a sort control: shows a chevron reflecting the
// current sort direction and toggles asc -> desc -> none on click. Pairs with
// useSort(). When rendered inside a <ResizableTable>, it also exposes a drag
// handle on its right edge so the column can be resized (keyed by sortKey).

import { ChevronDown, ChevronUp, ChevronsUpDown } from "lucide-react";
import { TableHead } from "@/components/ui/table";
import { ColResizer, useColumnWidth } from "@/components/ResizableTable";
import type { SortDirection, SortState } from "@/lib/useSort";
import { cn } from "@/lib/utils";

export function SortableHead<K extends string>({
  sortKey,
  sort,
  onToggle,
  className,
  align = "left",
  children,
}: {
  sortKey: K;
  sort: SortState<K>;
  onToggle: (key: K) => void;
  className?: string;
  align?: "left" | "right";
  children: React.ReactNode;
}) {
  const active = sort.key === sortKey;
  const widthCtx = useColumnWidth();
  const width = widthCtx?.widthOf(sortKey);
  return (
    <TableHead
      className={cn("relative", className)}
      data-col-key={sortKey}
      style={width ? { width, maxWidth: width } : undefined}
    >
      <button
        type="button"
        onClick={() => onToggle(sortKey)}
        className={cn(
          "group inline-flex max-w-full select-none items-center gap-1 truncate transition-colors hover:text-foreground",
          align === "right" && "flex-row-reverse",
          active && "text-foreground",
        )}
      >
        {children}
        <SortIcon active={active} direction={sort.direction} />
      </button>
      <ColResizer colKey={sortKey} />
    </TableHead>
  );
}

function SortIcon({ active, direction }: { active: boolean; direction: SortDirection }) {
  if (!active)
    return (
      <ChevronsUpDown className="h-3.5 w-3.5 shrink-0 opacity-40 transition-opacity group-hover:opacity-70" />
    );
  return direction === "asc" ? (
    <ChevronUp className="h-3.5 w-3.5 shrink-0" />
  ) : (
    <ChevronDown className="h-3.5 w-3.5 shrink-0" />
  );
}
