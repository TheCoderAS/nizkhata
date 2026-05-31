// Generic detail modal: a titled dialog that renders label/value field rows and
// an optional actions menu in the header + footer. Used when a table row is
// clicked, across every screen, for a consistent "view details" experience.
//
// Keeps itself mounted briefly after close so Radix can play the exit
// animation (callers conditionally render this, which would otherwise unmount
// it instantly and skip the closing transition).

import { useEffect, useState, type ReactNode } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { RowActions, type RowAction } from "@/components/RowActions";
import { AuditFooter, RevisionHistory } from "@/components/RevisionHistory";
import type { Actor, Ts } from "@/types/models";
import { cn } from "@/lib/utils";

export interface DetailField {
  label: string;
  value: ReactNode;
  /** render value full-width below the label instead of inline (for long text) */
  block?: boolean;
  hidden?: boolean;
}

export function DetailDialog({
  open,
  onClose,
  title,
  fields,
  actions = [],
  children,
  entityId,
  audit,
}: {
  open: boolean;
  onClose: () => void;
  title: ReactNode;
  fields: DetailField[];
  actions?: RowAction[];
  children?: ReactNode;
  /** when set, shows an audit footer + collapsible revision history */
  entityId?: string;
  audit?: {
    createdBy?: Actor;
    createdAt?: Ts;
    updatedBy?: Actor;
    updatedAt?: Ts;
  };
}) {
  // Mirror `open` into local state so we can run the close animation before the
  // parent unmounts us.
  const [show, setShow] = useState(open);
  const [showHistory, setShowHistory] = useState(false);
  useEffect(() => setShow(open), [open]);

  function handleOpenChange(next: boolean) {
    if (!next) {
      setShow(false);
      // let the exit animation (~200ms) finish before the parent unmounts
      window.setTimeout(onClose, 200);
    }
  }

  const visible = fields.filter((f) => !f.hidden);

  return (
    <Dialog open={show} onOpenChange={handleOpenChange}>
      {/* hide the built-in close so the kebab + close share one row */}
      <DialogContent className="max-w-lg" hideClose>
        <DialogHeader>
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0 space-y-1">
              <DialogTitle className="truncate text-lg">{title}</DialogTitle>
            </div>
            <div className="flex shrink-0 items-center gap-1">
              {actions.length > 0 && <RowActions actions={actions} />}
              <CloseButton onClick={() => handleOpenChange(false)} />
            </div>
          </div>
        </DialogHeader>

        <dl className="divide-y">
          {visible.map((f) => (
            <div
              key={f.label}
              className={cn(
                "py-2.5",
                f.block ? "space-y-1" : "flex items-start justify-between gap-4",
              )}
            >
              <dt className="shrink-0 text-sm text-muted-foreground">{f.label}</dt>
              <dd className={cn("text-sm font-medium", !f.block && "text-right")}>
                {f.value}
              </dd>
            </div>
          ))}
        </dl>

        {children}

        {audit && <AuditFooter {...audit} />}

        {entityId && (
          <div className="border-t pt-2">
            <button
              type="button"
              onClick={() => setShowHistory((s) => !s)}
              className="text-xs font-medium text-muted-foreground hover:text-foreground"
            >
              {showHistory ? "Hide history" : "View history"}
            </button>
            {showHistory && (
              <div className="mt-2">
                <RevisionHistory entityId={entityId} />
              </div>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

function CloseButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label="Close"
      className="inline-flex h-8 w-8 items-center justify-center rounded-md text-muted-foreground opacity-70 transition-opacity hover:bg-accent hover:opacity-100 focus:outline-none focus:ring-2 focus:ring-ring"
    >
      <svg
        className="h-4 w-4"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M18 6 6 18M6 6l12 12" />
      </svg>
    </button>
  );
}
