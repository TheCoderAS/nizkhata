// Sidebar nav (§6 app shell). Two views inside one rail:
//   - "main": Dashboard … Reports, then a Settings button (chevron).
//   - "settings": a back button + "Settings" heading + the settings options.
// Clicking Settings slides into the settings view; Back returns to main.
// The view auto-syncs to whether you're on a /settings/* route.

import { useEffect, useState } from "react";
import { NavLink, useLocation } from "react-router-dom";
import {
  LayoutDashboard,
  ArrowLeftRight,
  CalendarClock,
  Users,
  HandCoins,
  Wallet,
  Split,
  Tags,
  Target,
  UserCog,
  ShieldCheck,
  Building2,
  CircleUser,
  Settings,
  ChevronRight,
  ChevronLeft,
  type LucideIcon,
} from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useSharedData } from "@/data/SharedDataProvider";
import type { Permission } from "@/types/permissions";
import { cn } from "@/lib/utils";
import { Logo } from "@/components/Logo";

interface NavItem {
  to: string;
  label: string;
  icon: LucideIcon;
  perm?: Permission; // undefined = always visible
}

export type { NavItem };

export const MAIN_NAV: NavItem[] = [
  { to: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { to: "/transactions", label: "Transactions", icon: ArrowLeftRight, perm: "transactions.view" },
  { to: "/dues", label: "Dues", icon: CalendarClock, perm: "dues.view" },
  { to: "/contacts", label: "Contacts", icon: Users, perm: "contacts.view" },
  { to: "/debts", label: "Debts", icon: HandCoins, perm: "debts.view" },
  { to: "/shared", label: "Shared", icon: Split, perm: "shared.view" },
  // Reports + Activity are surfaced in the top header (icon + bell), not here.
];

const SETTINGS_NAV: NavItem[] = [
  { to: "/settings/accounts", label: "Accounts", icon: Wallet, perm: "accounts.view" },
  { to: "/settings/categories", label: "Categories", icon: Tags, perm: "categories.view" },
  { to: "/settings/budgets", label: "Budgets", icon: Target, perm: "categories.view" },
  { to: "/settings/members", label: "Members", icon: UserCog, perm: "members.view" },
  { to: "/settings/roles", label: "Roles", icon: ShieldCheck, perm: "roles.view" },
  { to: "/settings/workspace", label: "Workspace", icon: Building2, perm: "workspace.edit" },
  { to: "/settings/account", label: "Profile", icon: CircleUser },
];

function itemClass(isActive: boolean) {
  return cn(
    "group flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-all duration-150",
    isActive
      ? "brand-gradient text-primary-foreground shadow-md shadow-primary/25"
      : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
  );
}

function NavItemLink({
  item,
  onNavigate,
  badge,
}: {
  item: NavItem;
  onNavigate?: () => void;
  badge?: number;
}) {
  const Icon = item.icon;
  return (
    <NavLink
      to={item.to}
      end={item.to === "/"}
      onClick={onNavigate}
      className={({ isActive }) => itemClass(isActive)}
    >
      <Icon className="h-4 w-4 shrink-0 transition-transform duration-150 group-hover:scale-110" />
      {item.label}
      {badge !== undefined && badge > 0 && (
        <span className="ml-auto flex h-5 min-w-5 items-center justify-center rounded-full bg-primary px-1.5 text-[11px] font-semibold text-primary-foreground">
          {badge}
        </span>
      )}
    </NavLink>
  );
}

/** Sidebar inner content, shared by the desktop rail and the mobile drawer. */
export function SidebarContent({
  onNavigate,
  initialView,
}: {
  onNavigate?: () => void;
  /** Open straight into a view (e.g. the mobile "More" button -> settings). */
  initialView?: "main" | "settings";
}) {
  const { can, activeWorkspace } = useWorkspace();
  const { firebaseUser } = useAuth();
  const { inboxCount } = useSharedData();
  const location = useLocation();
  const onSettingsRoute = location.pathname.startsWith("/settings");
  const [view, setView] = useState<"main" | "settings">(
    initialView ?? (onSettingsRoute ? "settings" : "main"),
  );

  // keep the view in sync when navigating into/out of settings elsewhere
  useEffect(() => {
    if (onSettingsRoute) setView("settings");
  }, [onSettingsRoute]);

  const mainItems = MAIN_NAV.filter((i) => !i.perm || can(i.perm));
  const settingsItems = SETTINGS_NAV.filter((i) => !i.perm || can(i.perm));

  return (
    <div className="flex h-full flex-col gap-4 overflow-hidden p-3">
      {/* brand */}
      <div className="px-2 pt-1">
        <Logo size="sm" />
      </div>

      {/* sliding views */}
      <div className="relative flex-1 overflow-hidden">
        {view === "main" ? (
          <nav className="flex animate-fade-in flex-col gap-1">
            {mainItems.map((item) => (
              <NavItemLink
                key={item.to}
                item={item}
                onNavigate={onNavigate}
                badge={item.to === "/shared" ? inboxCount : undefined}
              />
            ))}
            {settingsItems.length > 0 && (
              <button
                type="button"
                onClick={() => setView("settings")}
                className={cn(
                  "group mt-1 flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                  onSettingsRoute
                    ? "text-foreground"
                    : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
                )}
              >
                <Settings className="h-4 w-4 shrink-0 transition-transform duration-150 group-hover:scale-110" />
                Settings
                <ChevronRight className="ml-auto h-4 w-4" />
              </button>
            )}
          </nav>
        ) : (
          <div className="flex animate-fade-in flex-col gap-1">
            <button
              type="button"
              onClick={() => setView("main")}
              className="flex items-center gap-2 rounded-lg px-2 py-2 text-sm text-muted-foreground transition-colors hover:text-foreground"
            >
              <ChevronLeft className="h-4 w-4" />
              Back
            </button>
            <p className="px-3 pb-1 pt-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground/70">
              Settings
            </p>
            <nav className="flex flex-col gap-1">
              {settingsItems.map((item) => (
                <NavItemLink key={item.to} item={item} onNavigate={onNavigate} />
              ))}
            </nav>
          </div>
        )}
      </div>

      {/* account footer — fills the empty bottom + gives drawer users a way to
          reach their account while the header avatar menu is hidden */}
      <NavLink
        to="/settings/account"
        onClick={onNavigate}
        className={({ isActive }) =>
          cn(
            "mt-auto flex items-center gap-3 rounded-lg border p-2 text-left transition-colors",
            isActive ? "bg-accent" : "hover:bg-accent",
          )
        }
      >
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-semibold text-primary-foreground">
          {actorInitials(
            firebaseUser?.displayName ?? firebaseUser?.email ?? "?",
          )}
        </span>
        <span className="min-w-0 flex-1 leading-tight">
          <span className="block truncate text-sm font-medium">
            {firebaseUser?.displayName ?? firebaseUser?.email ?? "Account"}
          </span>
          <span className="block truncate text-xs text-muted-foreground">
            {activeWorkspace?.name ?? "—"}
          </span>
        </span>
      </NavLink>
    </div>
  );
}

function actorInitials(nameOrEmail: string): string {
  const parts = nameOrEmail.trim().split(/[\s@.]+/).filter(Boolean);
  return (parts[0]?.[0] ?? "?").toUpperCase() + (parts[1]?.[0]?.toUpperCase() ?? "");
}

/** Fixed desktop rail (hidden on mobile). */
export function Sidebar() {
  return (
    <aside className="hidden w-64 shrink-0 border-r border-border/60 bg-card/40 backdrop-blur-xl md:block">
      <SidebarContent />
    </aside>
  );
}
