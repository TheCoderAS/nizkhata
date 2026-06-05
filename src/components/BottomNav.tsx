// Mobile bottom navigation bar (md:hidden). Shows the first few permitted
// primary destinations plus a "Settings" button that opens the nav drawer
// straight in its settings view. Mirrors MAIN_NAV so it stays in sync.

import { NavLink, useLocation } from "react-router-dom";
import { Settings } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { MAIN_NAV } from "./Sidebar";
import { cn } from "@/lib/utils";

// How many primary links to show before the "Settings" button.
const MAX_ITEMS = 5;

export function BottomNav({ onMore }: { onMore: () => void }) {
  const { can } = useWorkspace();
  const location = useLocation();

  const items = MAIN_NAV.filter((i) => !i.perm || can(i.perm)).slice(0, MAX_ITEMS);
  const shownPaths = new Set(items.map((i) => i.to));
  // Highlight "Settings" when the current route isn't one of the visible tabs
  // (e.g. a /settings/* route, or an overflow destination via the drawer).
  const moreActive = !shownPaths.has(location.pathname);

  // Index of the active tab (Settings is the trailing slot) so a single pill can
  // slide between tabs rather than each one toggling independently.
  const tabCount = items.length + 1;
  const activeIndex = moreActive
    ? items.length
    : items.findIndex((i) =>
        i.to === "/"
          ? location.pathname === "/"
          : location.pathname === i.to || location.pathname.startsWith(i.to + "/"),
      );

  return (
    <nav
      className="glass fixed inset-x-0 bottom-0 z-30 flex rounded-none border-x-0 border-b-0 pb-[env(safe-area-inset-bottom)] md:hidden"
      aria-label="Primary"
    >
      {/* Sliding active indicator (a short pill at the top edge). */}
      {activeIndex >= 0 && (
        <span
          aria-hidden
          className="pointer-events-none absolute top-0 h-0.5 rounded-full bg-primary transition-[left] duration-300 ease-out"
          style={{
            width: `calc(${100 / tabCount}% - 2rem)`,
            left: `calc(${(activeIndex + 0.5) * (100 / tabCount)}% - (${100 / tabCount}% - 2rem) / 2)`,
          }}
        />
      )}
      {items.map((item) => {
        const Icon = item.icon;
        return (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.to === "/"}
            className={({ isActive }) =>
              cn(
                "flex flex-1 flex-col items-center justify-center gap-0.5 py-2 text-[11px] font-medium transition-colors",
                isActive ? "text-primary" : "text-muted-foreground hover:text-foreground",
              )
            }
          >
            <Icon className="h-5 w-5" />
            <span className="max-w-full truncate px-0.5">{item.label}</span>
          </NavLink>
        );
      })}
      <button
        type="button"
        onClick={onMore}
        className={cn(
          "flex flex-1 flex-col items-center justify-center gap-0.5 py-2 text-[11px] font-medium transition-colors",
          moreActive ? "text-primary" : "text-muted-foreground hover:text-foreground",
        )}
      >
        <Settings className="h-5 w-5" />
        <span>Settings</span>
      </button>
    </nav>
  );
}
