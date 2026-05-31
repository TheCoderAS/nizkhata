// Dropdown to show/hide table columns. Pairs with useColumnPrefs.

import { SlidersHorizontal } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import type { ColumnDef } from "@/lib/useColumnPrefs";

export function ColumnsMenu<K extends string>({
  columns,
  isVisible,
  toggle,
  reset,
}: {
  columns: ColumnDef<K>[];
  isVisible: (key: K) => boolean;
  toggle: (key: K) => void;
  reset: () => void;
}) {
  const toggleable = columns.filter((c) => !c.locked);
  if (toggleable.length === 0) return null;

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="icon" aria-label="Columns" title="Columns">
          <SlidersHorizontal className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-48">
        <DropdownMenuLabel>Columns</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {toggleable.map((c) => (
          <DropdownMenuCheckboxItem
            key={c.key}
            checked={isVisible(c.key)}
            onSelect={(e) => {
              e.preventDefault(); // keep the menu open for multiple toggles
              toggle(c.key);
            }}
          >
            {c.label}
          </DropdownMenuCheckboxItem>
        ))}
        <DropdownMenuSeparator />
        <DropdownMenuItem onSelect={() => reset()}>Reset to default</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
