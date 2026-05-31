// Client-side pagination for already-sorted/filtered table rows. Returns the
// current page slice plus the controls a <Pagination> footer needs. The page
// auto-clamps when the underlying list shrinks (e.g. after filtering), so you
// never get stranded on an empty page.

import { useEffect, useMemo, useState } from "react";

export const DEFAULT_PAGE_SIZE = 25;

export function usePagination<T>(rows: T[], pageSize: number = DEFAULT_PAGE_SIZE) {
  const [page, setPage] = useState(0);

  const pageCount = Math.max(1, Math.ceil(rows.length / pageSize));

  // Clamp the page when the row count changes (filtering, deletion, …).
  useEffect(() => {
    if (page > pageCount - 1) setPage(pageCount - 1);
  }, [page, pageCount]);

  const pageItems = useMemo(
    () => rows.slice(page * pageSize, page * pageSize + pageSize),
    [rows, page, pageSize],
  );

  return {
    pageItems,
    page,
    pageCount,
    pageSize,
    total: rows.length,
    setPage,
    next: () => setPage((p) => Math.min(p + 1, pageCount - 1)),
    prev: () => setPage((p) => Math.max(p - 1, 0)),
    // Call when filters/search change to jump back to the first page.
    reset: () => setPage(0),
  };
}

export type PaginationState<T> = ReturnType<typeof usePagination<T>>;
