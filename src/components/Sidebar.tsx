// Sidebar nav (§6 app shell). Workspace switcher + permission-gated nav items.
// Items the user lacks permission for are HIDDEN, not disabled. Icons + active
// indicator; used both as a fixed desktop rail and inside the mobile drawer.

import { NavLink } from "react-router-dom";
import {
  LayoutDashboard,
  ArrowLeftRight,
  CalendarClock,
  Users,
  Wallet,
  Tags,
  HandCoins,
  BarChart3,
  UserCog,
  ShieldCheck,
  Building2,
  type LucideIcon,
} from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { Permission } from "@/types/permissions";
import { cn } from "@/lib/utils";

interface NavItem {
  to: string;
  label: string;
  icon: LucideIcon;
  perm?: Permission; // undefined = always visible (e.g. Dashboard)
}

const MAIN_NAV: NavItem[] = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard },
  { to: "/transactions", label: "Transactions", icon: ArrowLeftRight, perm: "transactions.view" },
  { to: "/dues", label: "Dues", icon: CalendarClock, perm: "dues.view" },
  { to: "/contacts", label: "Contacts", icon: Users, perm: "contacts.view" },
  { to: "/accounts", label: "Accounts", icon: Wallet, perm: "accounts.view" },
  { to: "/categories", label: "Categories", icon: Tags, perm: "categories.view" },
  { to: "/debts", label: "Debts", icon: HandCoins, perm: "debts.view" },
  { to: "/reports", label: "Reports", icon: BarChart3, perm: "reports.view" },
];

const SETTINGS_NAV: NavItem[] = [
  { to: "/settings/members", label: "Members", icon: UserCog, perm: "members.view" },
  { to: "/settings/roles", label: "Roles", icon: ShieldCheck, perm: "roles.view" },
  { to: "/settings/workspace", label: "Workspace", icon: Building2, perm: "workspace.edit" },
];

function NavSection({
  items,
  onNavigate,
}: {
  items: NavItem[];
  onNavigate?: () => void;
}) {
  const { can } = useWorkspace();
  const visible = items.filter((i) => !i.perm || can(i.perm));
  return (
    <nav className="flex flex-col gap-1">
      {visible.map((item) => {
        const Icon = item.icon;
        return (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.to === "/"}
            onClick={onNavigate}
            className={({ isActive }) =>
              cn(
                "group flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-all duration-150",
                isActive
                  ? "bg-primary text-primary-foreground shadow-sm"
                  : "text-muted-foreground hover:bg-accent hover:text-accent-foreground",
              )
            }
          >
            <Icon className="h-4 w-4 shrink-0 transition-transform duration-150 group-hover:scale-110" />
            {item.label}
          </NavLink>
        );
      })}
    </nav>
  );
}

function WorkspaceSwitcher() {
  const { workspaces, activeWorkspaceId, switchWorkspace } = useWorkspace();
  if (workspaces.length === 0) return null;
  return (
    <Select value={activeWorkspaceId ?? ""} onValueChange={switchWorkspace}>
      <SelectTrigger className="w-full">
        <SelectValue placeholder="Workspace" />
      </SelectTrigger>
      <SelectContent>
        {workspaces.map((w) => (
          <SelectItem key={w.id} value={w.id}>
            {w.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

/** Sidebar inner content, shared by the desktop rail and the mobile drawer. */
export function SidebarContent({ onNavigate }: { onNavigate?: () => void }) {
  const { can } = useWorkspace();
  const showSettings = SETTINGS_NAV.some((i) => !i.perm || can(i.perm));
  return (
    <div className="flex h-full flex-col gap-5 p-3">
      <div className="flex items-center gap-2 px-2 pt-1">
        <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-base font-bold text-primary-foreground">
          ₹
        </div>
        <span className="font-semibold tracking-tight">NizKhata</span>
      </div>
      <WorkspaceSwitcher />
      <NavSection items={MAIN_NAV} onNavigate={onNavigate} />
      {showSettings && (
        <div className="mt-auto">
          <p className="px-3 pb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground/70">
            Settings
          </p>
          <NavSection items={SETTINGS_NAV} onNavigate={onNavigate} />
        </div>
      )}
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
