// App shell: responsive top bar (mobile menu + an avatar menu showing the active
// workspace) + desktop sidebar rail + mobile drawer + routed content (§6).

import { Suspense, useState, type ComponentType } from "react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import { LogOut, ArrowLeftRight, BarChart3, Bell } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { cn } from "@/lib/utils";
import { Logo } from "@/components/Logo";
import { Sidebar, SidebarContent } from "./Sidebar";
import { BottomNav } from "./BottomNav";
import { WorkspaceSwitcherDialog } from "./WorkspaceSwitcherDialog";
import { ErrorState, FullScreenLoader, PageSkeleton } from "./states";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

function workspaceInitials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  return (parts[0][0] + (parts[1]?.[0] ?? "")).toUpperCase();
}

function HeaderIconLink({
  to,
  label,
  icon: Icon,
}: {
  to: string;
  label: string;
  icon: ComponentType<{ className?: string }>;
}) {
  return (
    <NavLink
      to={to}
      aria-label={label}
      title={label}
      className={({ isActive }) =>
        cn(
          "flex h-10 w-10 items-center justify-center rounded-full transition-colors",
          isActive
            ? "bg-primary/10 text-primary"
            : "text-muted-foreground hover:bg-accent hover:text-foreground",
        )
      }
    >
      <Icon className="h-5 w-5" />
    </NavLink>
  );
}

export function AppShell() {
  const { firebaseUser, signOut } = useAuth();
  const { loading, error, memberships, activeWorkspace, can } = useWorkspace();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [switcherOpen, setSwitcherOpen] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();

  if (loading) return <FullScreenLoader label="Loading workspace…" />;
  if (error) return <ErrorState message={error} />;

  const hasNav = memberships.length > 0;
  const wsName = activeWorkspace?.name ?? "Workspace";
  const userName = firebaseUser?.displayName ?? firebaseUser?.email ?? "User";

  return (
    <div className="flex h-screen overflow-hidden">
      {hasNav && <Sidebar />}

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="glass sticky top-0 z-20 flex h-14 shrink-0 items-center gap-2 rounded-none border-x-0 border-t-0 px-3 sm:px-4">
          <div className="flex items-center gap-2 md:hidden">
            <Logo size="sm" />
          </div>

          {/* ml-auto keeps this group right-aligned even on desktop, where the
              mobile logo above is hidden (a lone justify-between child would
              otherwise sit at the start). */}
          <div className="ml-auto flex items-center gap-1">
            {can("reports.view") && (
              <HeaderIconLink to="/reports" label="Reports" icon={BarChart3} />
            )}
            {can("reports.view") && (
              <HeaderIconLink to="/activity" label="Activity" icon={Bell} />
            )}

            <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" className="h-11 gap-2 px-2" aria-label="Workspace menu">
                <span className="flex h-8 w-8 items-center justify-center rounded-full bg-primary text-xs font-semibold text-primary-foreground">
                  {workspaceInitials(wsName)}
                </span>
                <span className="hidden min-w-0 flex-col items-start leading-tight sm:flex">
                  <span className="max-w-[180px] truncate text-sm font-medium">{wsName}</span>
                  <span className="max-w-[180px] truncate text-xs text-muted-foreground">
                    {userName}
                  </span>
                </span>
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-64">
              <DropdownMenuLabel className="flex flex-col gap-0.5">
                <span className="truncate font-medium">{wsName}</span>
                <span className="truncate text-xs font-normal text-muted-foreground">
                  {firebaseUser?.email}
                </span>
              </DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuItem onClick={() => setSwitcherOpen(true)}>
                <ArrowLeftRight className="mr-2 h-4 w-4" />
                Switch workspace
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onClick={() => {
                  void signOut().then(() => navigate("/"));
                }}
              >
                <LogOut className="mr-2 h-4 w-4" />
                Sign out
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          </div>
        </header>

        <main className="min-h-0 flex-1 overflow-auto">
          {/* key on pathname so each route fades in on navigation */}
          <div
            key={location.pathname}
            className="mx-auto max-w-6xl animate-fade-in-up p-4 pb-20 sm:p-6 md:pb-6"
          >
            {/* Lazy-loaded pages suspend while their chunk downloads; keep the
                shell/nav visible and show a page skeleton in the content. */}
            <Suspense fallback={<PageSkeleton />}>
              <Outlet />
            </Suspense>
          </div>
        </main>
      </div>

      {hasNav && <BottomNav onMore={() => setDrawerOpen(true)} />}

      {/* Mobile drawer */}
      <Dialog open={drawerOpen} onOpenChange={setDrawerOpen}>
        <DialogContent
          hideClose
          className="left-0 top-0 h-full max-w-[17rem] translate-x-0 translate-y-0 gap-0 rounded-none border-y-0 border-l-0 p-0 data-[state=closed]:slide-out-to-left data-[state=open]:slide-in-from-left sm:rounded-none"
        >
          <DialogTitle className="sr-only">Navigation</DialogTitle>
          <SidebarContent initialView="settings" onNavigate={() => setDrawerOpen(false)} />
        </DialogContent>
      </Dialog>

      <WorkspaceSwitcherDialog open={switcherOpen} onOpenChange={setSwitcherOpen} />
    </div>
  );
}
