// A "Filters" button (with an active-count badge) that opens a modal holding the
// filter controls. Used to move per-page filters off the toolbar into a dialog.

import type { ReactNode } from "react";
import { Filter } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

/** A labelled row inside the filter modal. */
export function FilterRow({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <span className="text-sm font-medium">{label}</span>
      {children}
    </div>
  );
}

export function FilterModal({
  activeCount,
  onClear,
  children,
}: {
  /** number of non-default filters currently applied (shows a badge) */
  activeCount: number;
  /** reset all filters */
  onClear: () => void;
  /** the filter controls (selects, toggles, …) */
  children: ReactNode;
}) {
  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button variant="outline" className="gap-2">
          <Filter className="h-4 w-4" />
          Filters
          {activeCount > 0 && (
            <Badge variant="default" className="ml-1 px-1.5">
              {activeCount}
            </Badge>
          )}
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Filters</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">{children}</div>
        <DialogFooter className="sm:justify-between">
          <Button variant="ghost" onClick={onClear} disabled={activeCount === 0}>
            Clear all
          </Button>
          {/* Dialog close lives in the header (x); this is just the primary CTA */}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
