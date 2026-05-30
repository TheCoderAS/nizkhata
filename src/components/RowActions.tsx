// Kebab (⋯) row-actions menu. Used in table rows and detail modals so actions
// live in one consistent dropdown instead of scattered icon buttons.
//
// Stops click propagation so opening the menu from a clickable row doesn't also
// trigger the row's onClick (e.g. the detail modal).

import { MoreHorizontal, type LucideIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";

export interface RowAction {
  label: string;
  icon?: LucideIcon;
  onSelect: () => void;
  destructive?: boolean;
  disabled?: boolean;
  separatorBefore?: boolean;
  hidden?: boolean;
}

export function RowActions({
  actions,
  align = "end",
  label = "Actions",
  size = "icon",
}: {
  actions: RowAction[];
  align?: "start" | "end";
  label?: string;
  size?: "icon" | "sm";
}) {
  const visible = actions.filter((a) => !a.hidden);
  if (visible.length === 0) return null;

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild onClick={(e) => e.stopPropagation()}>
        <Button
          variant="ghost"
          size={size === "icon" ? "icon" : "sm"}
          aria-label={label}
          className={cn(size === "sm" && "gap-1")}
        >
          <MoreHorizontal className="h-4 w-4" />
          {size === "sm" && <span>{label}</span>}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align={align} onClick={(e) => e.stopPropagation()}>
        {visible.map((action, i) => {
          const Icon = action.icon;
          return (
            <div key={action.label}>
              {action.separatorBefore && i > 0 && <DropdownMenuSeparator />}
              <DropdownMenuItem
                disabled={action.disabled}
                onSelect={(e) => {
                  e.preventDefault();
                  action.onSelect();
                }}
                className={cn(
                  action.destructive &&
                    "text-destructive focus:bg-destructive/10 focus:text-destructive",
                )}
              >
                {Icon && <Icon className="mr-2 h-4 w-4" />}
                {action.label}
              </DropdownMenuItem>
            </div>
          );
        })}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
