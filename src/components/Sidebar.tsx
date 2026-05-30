// Sidebar nav (§6 app shell). Workspace switcher + permission-gated nav items.
// Items the user lacks permission for are HIDDEN, not disabled.

import { NavLink } from "react-router-dom";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import type { Permission } from "@/types/permissions";

interface NavItem {
  to: string;
  label: string;
  perm?: Permission; // undefined = always visible (e.g. Dashboard)
}

const MAIN_NAV: NavItem[] = [
  { to: "/", label: "Dashboard" },
  { to: "/transactions", label: "Transactions", perm: "transactions.view" },
  { to: "/dues", label: "Dues", perm: "dues.view" },
  { to: "/contacts", label: "Contacts", perm: "contacts.view" },
  { to: "/accounts", label: "Accounts", perm: "accounts.view" },
  { to: "/categories", label: "Categories", perm: "categories.view" },
  { to: "/debts", label: "Debts", perm: "debts.view" },
  { to: "/reports", label: "Reports", perm: "reports.view" },
];

const SETTINGS_NAV: NavItem[] = [
  { to: "/settings/members", label: "Members", perm: "members.view" },
  { to: "/settings/roles", label: "Roles", perm: "roles.view" },
  { to: "/settings/workspace", label: "Workspace", perm: "workspace.edit" },
];

function NavSection({ items }: { items: NavItem[] }) {
  const { can } = useWorkspace();
  const visible = items.filter((i) => !i.perm || can(i.perm));
  return (
    <nav className="flex flex-col gap-0.5">
      {visible.map((item) => (
        <NavLink
          key={item.to}
          to={item.to}
          end={item.to === "/"}
          className={({ isActive }) =>
            `rounded-md px-3 py-2 text-sm ${
              isActive
                ? "bg-gray-900 text-white"
                : "text-gray-700 hover:bg-gray-100"
            }`
          }
        >
          {item.label}
        </NavLink>
      ))}
    </nav>
  );
}

function WorkspaceSwitcher() {
  const { workspaces, activeWorkspaceId, switchWorkspace } = useWorkspace();
  if (workspaces.length === 0) return null;
  return (
    <select
      className="w-full rounded-md border border-gray-300 bg-white px-2 py-2 text-sm"
      value={activeWorkspaceId ?? ""}
      onChange={(e) => switchWorkspace(e.target.value)}
    >
      {workspaces.map((w) => (
        <option key={w.id} value={w.id}>
          {w.name}
        </option>
      ))}
    </select>
  );
}

export function Sidebar() {
  const { can } = useWorkspace();
  const showSettings = SETTINGS_NAV.some((i) => !i.perm || can(i.perm));
  return (
    <aside className="flex w-60 shrink-0 flex-col gap-4 border-r border-gray-200 bg-gray-50 p-3">
      <WorkspaceSwitcher />
      <NavSection items={MAIN_NAV} />
      {showSettings && (
        <div className="mt-auto">
          <p className="px-3 pb-1 text-xs font-semibold uppercase tracking-wide text-gray-400">
            Settings
          </p>
          <NavSection items={SETTINGS_NAV} />
        </div>
      )}
    </aside>
  );
}
