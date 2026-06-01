import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { Button } from "@/components/ui/button";

export interface PrimaryAction {
  label: string;
  icon: LucideIcon;
  onClick: () => void;
  hidden?: boolean;
}

export function PageHeader({
  title,
  actions,
  primaryAction,
}: {
  title: string;
  /** extra custom controls (e.g. a filter select) rendered before the primary action */
  actions?: ReactNode;
  /** the main page action — renders icon-only on mobile, icon+label on desktop */
  primaryAction?: PrimaryAction;
}) {
  return (
    <div className="mb-5 flex items-center justify-between gap-4">
      <h1 className="text-2xl font-semibold tracking-tight sm:text-[1.75rem]">{title}</h1>
      <div className="flex shrink-0 items-center gap-2">
        {actions}
        {primaryAction && !primaryAction.hidden && (
          <>
            {/* mobile: rounded icon button */}
            <Button
              size="icon"
              className="rounded-full sm:hidden"
              aria-label={primaryAction.label}
              onClick={primaryAction.onClick}
            >
              <primaryAction.icon className="h-4 w-4" />
            </Button>
            {/* desktop: icon + label */}
            <Button
              className="hidden sm:inline-flex"
              onClick={primaryAction.onClick}
            >
              <primaryAction.icon className="h-4 w-4" />
              {primaryAction.label}
            </Button>
          </>
        )}
      </div>
    </div>
  );
}
