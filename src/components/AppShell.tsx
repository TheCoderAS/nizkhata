// App shell: responsive top bar (mobile menu + theme toggle + user menu) +
// desktop sidebar rail + mobile drawer + routed content (§6).

import { useState } from "react";
import { Outlet, useLocation } from "react-router-dom";
import { Menu, LogOut } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { Sidebar, SidebarContent } from "./Sidebar";
import { ThemeToggle } from "./ThemeToggle";
import { ErrorState, LoadingState } from "./states";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

function initials(nameOrEmail: string): string {
  const base = nameOrEmail.trim();
  if (!base) return "?";
  const parts = base.split(/[\s@.]+/).filter(Boolean);
  return (parts[0]?.[0] ?? "?").toUpperCase() + (parts[1]?.[0]?.toUpperCase() ?? "");
}

export function AppShell() {
  const { firebaseUser, signOut } = useAuth();
  const { loading, error, memberships } = useWorkspace();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const location = useLocation();

  if (loading) return <LoadingState label="Loading workspace…" />;
  if (error) return <ErrorState message={error} />;

  const hasNav = memberships.length > 0;
  const displayName = firebaseUser?.displayName ?? firebaseUser?.email ?? "User";

  return (
    <div className="flex h-screen overflow-hidden">
      {hasNav && <Sidebar />}

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-14 shrink-0 items-center justify-between gap-2 border-b bg-card/80 px-3 backdrop-blur supports-[backdrop-filter]:bg-card/60 sm:px-4">
          <div className="flex items-center gap-2">
            {hasNav && (
              <Button
                variant="ghost"
                size="icon"
                className="md:hidden"
                aria-label="Open menu"
                onClick={() => setDrawerOpen(true)}
              >
                <Menu className="h-5 w-5" />
              </Button>
            )}
            <span className="font-semibold tracking-tight md:hidden">NizKhata</span>
          </div>

          <div className="flex items-center gap-1 sm:gap-2">
            <ThemeToggle />
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="ghost"
                  className="h-9 gap-2 px-2"
                  aria-label="Account menu"
                >
                  <span className="flex h-7 w-7 items-center justify-center rounded-full bg-primary text-xs font-semibold text-primary-foreground">
                    {initials(displayName)}
                  </span>
                  <span className="hidden max-w-[160px] truncate text-sm sm:inline">
                    {firebaseUser?.email}
                  </span>
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-56">
                <DropdownMenuLabel className="truncate font-normal text-muted-foreground">
                  {firebaseUser?.email}
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={() => void signOut()}>
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
            className="mx-auto max-w-6xl animate-fade-in-up p-4 sm:p-6"
          >
            <Outlet />
          </div>
        </main>
      </div>

      {/* Mobile drawer */}
      <Dialog open={drawerOpen} onOpenChange={setDrawerOpen}>
        <DialogContent className="left-0 top-0 h-full max-w-[17rem] translate-x-0 translate-y-0 gap-0 rounded-none border-y-0 border-l-0 p-0 data-[state=closed]:slide-out-to-left data-[state=open]:slide-in-from-left sm:rounded-none">
          <DialogTitle className="sr-only">Navigation</DialogTitle>
          <SidebarContent onNavigate={() => setDrawerOpen(false)} />
        </DialogContent>
      </Dialog>
    </div>
  );
}
