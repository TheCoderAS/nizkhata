// Standard pagination footer for list tables. Pairs with usePagination().
// Hidden automatically when everything fits on one page.

import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { PaginationState } from "@/lib/usePagination";

export function Pagination<T>({
  state,
  noun = "items",
}: {
  state: PaginationState<T>;
  /** plural noun for the count label, e.g. "transactions" */
  noun?: string;
}) {
  const { page, pageCount, total, prev, next } = state;
  if (pageCount <= 1) return null;

  return (
    <div className="mt-4 flex items-center justify-between gap-2 text-sm">
      <span className="text-muted-foreground">
        {total} {noun} · page {page + 1} of {pageCount}
      </span>
      <div className="flex gap-2">
        <Button size="sm" variant="outline" disabled={page === 0} onClick={prev}>
          <ChevronLeft className="h-4 w-4" />
          <span className="hidden sm:inline">Previous</span>
        </Button>
        <Button size="sm" variant="outline" disabled={page >= pageCount - 1} onClick={next}>
          <span className="hidden sm:inline">Next</span>
          <ChevronRight className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}
