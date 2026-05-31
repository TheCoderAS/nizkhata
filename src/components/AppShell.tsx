// App shell: responsive top bar (mobile menu + an avatar menu showing the active
// workspace) + desktop sidebar rail + mobile drawer + routed content (§6).

import { useState } from "react";
import { Outlet, useLocation } from "react-router-dom";
import { LogOut, ArrowLeftRight } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { Sidebar, SidebarContent } from "./Sidebar";
import { BottomNav } from "./BottomNav";
import { WorkspaceSwitcherDialog } from "./WorkspaceSwitcherDialog";
import { ErrorState, LoadingState } from "./states";
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

export function AppShell() {
  const { firebaseUser, signOut } = useAuth();
  const { loading, error, memberships, activeWorkspace } = useWorkspace();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [switcherOpen, setSwitcherOpen] = useState(false);
  const location = useLocation();

  if (loading) return <LoadingState label="Loading workspace…" />;
  if (error) return <ErrorState message={error} />;

  const hasNav = memberships.length > 0;
  const wsName = activeWorkspace?.name ?? "Workspace";
  const userName = firebaseUser?.displayName ?? firebaseUser?.email ?? "User";

  return (
    <div className="flex h-screen overflow-hidden">
      {hasNav && <Sidebar />}

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-14 shrink-0 items-center justify-between gap-2 border-b bg-card/80 px-3 backdrop-blur supports-[backdrop-filter]:bg-card/60 sm:px-4">
          <div className="flex items-center gap-2">
            <span className="font-semibold tracking-tight md:hidden">NizKhata</span>
          </div>

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
              <DropdownMenuItem onClick={() => void signOut()}>
                <LogOut className="mr-2 h-4 w-4" />
                Sign out
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </header>

        <main className="min-h-0 flex-1 overflow-auto">
          {/* key on pathname so each route fades in on navigation */}
          <div
            key={location.pathname}
            className="mx-auto max-w-6xl animate-fade-in-up p-4 pb-20 sm:p-6 md:pb-6"
          >
            <Outlet />
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
          <SidebarContent onNavigate={() => setDrawerOpen(false)} />
        </DialogContent>
      </Dialog>

      <WorkspaceSwitcherDialog open={switcherOpen} onOpenChange={setSwitcherOpen} />
    </div>
  );
}
