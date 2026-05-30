// App shell: responsive top bar (mobile menu + a single avatar menu holding
// workspace switch / theme / sign out) + desktop sidebar rail + mobile drawer +
// routed content (§6).

import { useState } from "react";
import { Outlet, useLocation } from "react-router-dom";
import { Menu, LogOut, Check, Sun, Moon, Laptop, Building2 } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useTheme, type Theme } from "@/theme/ThemeProvider";
import { Sidebar, SidebarContent } from "./Sidebar";
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
import { cn } from "@/lib/utils";

function initials(nameOrEmail: string): string {
  const base = nameOrEmail.trim();
  if (!base) return "?";
  const parts = base.split(/[\s@.]+/).filter(Boolean);
  return (parts[0]?.[0] ?? "?").toUpperCase() + (parts[1]?.[0]?.toUpperCase() ?? "");
}

const THEME_OPTIONS: { value: Theme; label: string; icon: typeof Sun }[] = [
  { value: "light", label: "Light", icon: Sun },
  { value: "dark", label: "Dark", icon: Moon },
  { value: "system", label: "System", icon: Laptop },
];

export function AppShell() {
  const { firebaseUser, signOut } = useAuth();
  const { loading, error, memberships, workspaces, activeWorkspaceId, switchWorkspace } =
    useWorkspace();
  const { theme, setTheme } = useTheme();
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

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" className="h-9 gap-2 px-2" aria-label="Account menu">
                <span className="flex h-7 w-7 items-center justify-center rounded-full bg-primary text-xs font-semibold text-primary-foreground">
                  {initials(displayName)}
                </span>
                <span className="hidden max-w-[160px] truncate text-sm sm:inline">
                  {firebaseUser?.email}
                </span>
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-64">
              <DropdownMenuLabel className="truncate font-normal text-muted-foreground">
                {firebaseUser?.email}
              </DropdownMenuLabel>

              {workspaces.length > 0 && (
                <>
                  <DropdownMenuSeparator />
                  <DropdownMenuLabel className="flex items-center gap-2 text-xs uppercase tracking-wide text-muted-foreground/70">
                    <Building2 className="h-3.5 w-3.5" /> Workspace
                  </DropdownMenuLabel>
                  {workspaces.map((w) => (
                    <DropdownMenuItem
                      key={w.id}
                      onClick={() => switchWorkspace(w.id)}
                      className={cn(activeWorkspaceId === w.id && "bg-accent")}
                    >
                      <span className="truncate">{w.name}</span>
                      {activeWorkspaceId === w.id && (
                        <Check className="ml-auto h-4 w-4" />
                      )}
                    </DropdownMenuItem>
                  ))}
                </>
              )}

              <DropdownMenuSeparator />
              <DropdownMenuLabel className="text-xs uppercase tracking-wide text-muted-foreground/70">
                Theme
              </DropdownMenuLabel>
              {THEME_OPTIONS.map((opt) => {
                const Icon = opt.icon;
                return (
                  <DropdownMenuItem
                    key={opt.value}
                    onClick={() => setTheme(opt.value)}
                    className={cn(theme === opt.value && "bg-accent")}
                  >
                    <Icon className="mr-2 h-4 w-4" />
                    {opt.label}
                    {theme === opt.value && <Check className="ml-auto h-4 w-4" />}
                  </DropdownMenuItem>
                );
              })}

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
            className="mx-auto max-w-6xl animate-fade-in-up p-4 sm:p-6"
          >
            <Outlet />
          </div>
        </main>
      </div>

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
    </div>
  );
}
