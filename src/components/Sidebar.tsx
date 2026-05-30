// Sidebar nav (§6 app shell). Workspace-scoped, permission-gated nav. Items the
// user lacks permission for are HIDDEN, not disabled. The Settings group is a
// collapsible section holding Accounts, Categories and the admin screens.

import { useState } from "react";
import { NavLink, useLocation } from "react-router-dom";
import {
  LayoutDashboard,
  ArrowLeftRight,
  CalendarClock,
  Users,
  HandCoins,
  BarChart3,
  Wallet,
  Tags,
  UserCog,
  ShieldCheck,
  Building2,
  CircleUser,
  Settings,
  ChevronDown,
  type LucideIcon,
} from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import type { Permission } from "@/types/permissions";
import { cn } from "@/lib/utils";

interface NavItem {
  to: string;
  label: string;
  icon: LucideIcon;
  perm?: Permission; // undefined = always visible
}

const MAIN_NAV: NavItem[] = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard },
  { to: "/transactions", label: "Transactions", icon: ArrowLeftRight, perm: "transactions.view" },
  { to: "/dues", label: "Dues", icon: CalendarClock, perm: "dues.view" },
  { to: "/contacts", label: "Contacts", icon: Users, perm: "contacts.view" },
  { to: "/debts", label: "Debts", icon: HandCoins, perm: "debts.view" },
  { to: "/reports", label: "Reports", icon: BarChart3, perm: "reports.view" },
];

// Settings group: data setup (accounts/categories) + admin + the personal
// Account page (always available).
const SETTINGS_NAV: NavItem[] = [
  { to: "/settings/accounts", label: "Accounts", icon: Wallet, perm: "accounts.view" },
  { to: "/settings/categories", label: "Categories", icon: Tags, perm: "categories.view" },
  { to: "/settings/members", label: "Members", icon: UserCog, perm: "members.view" },
  { to: "/settings/roles", label: "Roles", icon: ShieldCheck, perm: "roles.view" },
  { to: "/settings/workspace", label: "Workspace", icon: Building2, perm: "workspace.edit" },
  { to: "/settings/account", label: "Account", icon: CircleUser },
];

function itemClass(isActive: boolean) {
  return cn(
    "group flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-all duration-150",
    isActive
      ? "bg-primary text-primary-foreground shadow-sm"
      : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
  );
}

function NavItemLink({ item, onNavigate }: { item: NavItem; onNavigate?: () => void }) {
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
    </NavLink>
  );
}

function MainNav({ onNavigate }: { onNavigate?: () => void }) {
  const { can } = useWorkspace();
  const visible = MAIN_NAV.filter((i) => !i.perm || can(i.perm));
  return (
    <nav className="flex flex-col gap-1">
      {visible.map((item) => (
        <NavItemLink key={item.to} item={item} onNavigate={onNavigate} />
      ))}
    </nav>
  );
}

function SettingsGroup({ onNavigate }: { onNavigate?: () => void }) {
  const { can } = useWorkspace();
  const location = useLocation();
  const items = SETTINGS_NAV.filter((i) => !i.perm || can(i.perm));
  const sectionActive = location.pathname.startsWith("/settings");
  // open by default when on a settings route
  const [open, setOpen] = useState(sectionActive);

  if (items.length === 0) return null;

  return (
    <div>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className={cn(
          "flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
          sectionActive
            ? "text-foreground"
            : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
        )}
        aria-expanded={open}
      >
        <Settings className="h-4 w-4 shrink-0" />
        Settings
        <ChevronDown
          className={cn(
            "ml-auto h-4 w-4 transition-transform duration-200",
            open && "rotate-180",
          )}
        />
      </button>
      {open && (
        <nav className="mt-1 flex flex-col gap-1 border-l pl-3 ml-4">
          {items.map((item) => (
            <NavItemLink key={item.to} item={item} onNavigate={onNavigate} />
          ))}
        </nav>
      )}
    </div>
  );
}

/** Sidebar inner content, shared by the desktop rail and the mobile drawer. */
export function SidebarContent({ onNavigate }: { onNavigate?: () => void }) {
  return (
    <div className="flex h-full flex-col gap-5 overflow-y-auto p-3">
      <div className="flex items-center gap-2 px-2 pt-1">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-base font-bold text-primary-foreground">
          ₹
        </div>
        <span className="font-semibold tracking-tight">NizKhata</span>
      </div>
      <MainNav onNavigate={onNavigate} />
      <div className="mt-auto">
        <SettingsGroup onNavigate={onNavigate} />
      </div>
    </div>
  );
}

/** Fixed desktop rail (hidden on mobile). */
export function Sidebar() {
  return (
    <aside className="hidden w-64 shrink-0 border-r bg-card md:block">
      <SidebarContent />
    </aside>
  );
}
