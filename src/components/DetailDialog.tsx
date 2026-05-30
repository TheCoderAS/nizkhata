// Generic detail modal: a titled dialog that renders label/value field rows and
// an optional actions menu in the header + footer. Used when a table row is
// clicked, across every screen, for a consistent "view details" experience.

import type { ReactNode } from "react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { RowActions, type RowAction } from "@/components/RowActions";
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
  subtitle,
  fields,
  actions = [],
  children,
}: {
  open: boolean;
  onClose: () => void;
  title: ReactNode;
  subtitle?: ReactNode;
  fields: DetailField[];
  actions?: RowAction[];
  children?: ReactNode;
}) {
  const visible = fields.filter((f) => !f.hidden);
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <div className="flex items-start justify-between gap-2 pr-6">
            <DialogTitle className="text-lg">{title}</DialogTitle>
            {actions.length > 0 && <RowActions actions={actions} />}
          </div>
          {subtitle && <DialogDescription>{subtitle}</DialogDescription>}
        </DialogHeader>

        <dl className="divide-y">
          {visible.map((f) => (
            <div
              key={f.label}
              className={cn(
                "py-2.5",
                f.block
                  ? "space-y-1"
                  : "flex items-start justify-between gap-4",
              )}
            >
              <dt className="shrink-0 text-sm text-muted-foreground">{f.label}</dt>
              <dd
                className={cn(
                  "text-sm font-medium",
                  !f.block && "text-right",
                )}
              >
                {f.value}
              </dd>
            </div>
          ))}
        </dl>

        {children}
      </DialogContent>
    </Dialog>
  );
}
