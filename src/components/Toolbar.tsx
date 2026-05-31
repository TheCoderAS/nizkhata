// Standard list toolbar: a full-width row where the search input grows to fill
// available space and trailing controls (Filters, Columns, …) sit at the end.
// Used across list screens for a consistent layout.

import type { ReactNode } from "react";
import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";

export function Toolbar({
  search,
  onSearch,
  placeholder = "Search…",
  children,
}: {
  search: string;
  onSearch: (value: string) => void;
  placeholder?: string;
  /** trailing controls (FilterModal, ColumnsMenu, toggles…) */
  children?: ReactNode;
}) {
  return (
    <div className="mb-4 flex w-full items-center gap-2">
      <div className="relative min-w-0 flex-1">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={search}
          onChange={(e) => onSearch(e.target.value)}
          placeholder={placeholder}
          className="w-full pl-9"
        />
      </div>
      {children && <div className="flex shrink-0 items-center gap-2">{children}</div>}
    </div>
  );
}
