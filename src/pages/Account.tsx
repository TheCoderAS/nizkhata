// Settings › Account — the signed-in user's personal profile + preferences +
// the workspaces they belong to (with a "Leave" action). Profile fields come
// from the Google identity (read-only); theme mirrors the avatar menu.

import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { LogOut, Sun, Moon, Laptop, DoorOpen } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useTheme, type Theme } from "@/theme/ThemeProvider";
import { GuardrailError, leaveWorkspace } from "@/data/adminMutations";
import type { Workspace } from "@/types/models";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { useToast } from "@/components/ui/toast";
import { cn } from "@/lib/utils";

const THEME_OPTIONS: { value: Theme; label: string; icon: typeof Sun }[] = [
  { value: "light", label: "Light", icon: Sun },
  { value: "dark", label: "Dark", icon: Moon },
  { value: "system", label: "System", icon: Laptop },
];

export function Account() {
  const navigate = useNavigate();
  const { firebaseUser, signOut } = useAuth();
  const { theme, setTheme } = useTheme();
  const { workspaces, memberships, activeWorkspaceId, switchWorkspace } = useWorkspace();
  const { toast } = useToast();
  const uid = firebaseUser?.uid ?? "";

  const [toLeave, setToLeave] = useState<Workspace | null>(null);

  const myWorkspaces = workspaces
    .slice()
    .sort((a, b) => a.name.localeCompare(b.name));

  return (
    <div className="max-w-xl">
      <PageHeader title="Profile" />

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Profile</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center gap-4">
            {firebaseUser?.photoURL ? (
              <img
                src={firebaseUser.photoURL}
                alt=""
                className="h-14 w-14 rounded-full"
                referrerPolicy="no-referrer"
              />
            ) : (
              <div className="flex h-14 w-14 items-center justify-center rounded-full bg-primary text-lg font-semibold text-primary-foreground">
                {(firebaseUser?.displayName ?? firebaseUser?.email ?? "?")[0]?.toUpperCase()}
              </div>
            )}
            <div className="min-w-0">
              <p className="truncate font-medium">{firebaseUser?.displayName ?? "—"}</p>
              <p className="truncate text-sm text-muted-foreground">{firebaseUser?.email}</p>
            </div>
          </div>
          <p className="text-xs text-muted-foreground">
            Your name, email and photo come from your Google account.
          </p>
        </CardContent>
      </Card>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle className="text-base">Workspaces</CardTitle>
        </CardHeader>
        <CardContent>
          {myWorkspaces.length === 0 ? (
            <p className="text-sm text-muted-foreground">No workspaces.</p>
          ) : (
            <ul className="divide-y">
              {myWorkspaces.map((w) => {
                const isOwner = w.ownerId === uid;
                const isActive = w.id === activeWorkspaceId;
                return (
                  <li key={w.id} className="flex items-center justify-between gap-3 py-2.5 first:pt-0 last:pb-0">
                    <div className="flex min-w-0 items-center gap-2">
                      <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-primary text-xs font-semibold text-primary-foreground">
                        {w.name.slice(0, 2).toUpperCase()}
                      </span>
                      <span className="truncate font-medium">{w.name}</span>
                      {isActive && <Badge variant="secondary">Active</Badge>}
                    </div>
                    {isOwner ? (
                      <Badge variant="outline">Owner</Badge>
                    ) : (
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-destructive hover:text-destructive"
                        onClick={() => setToLeave(w)}
                      >
                        <DoorOpen className="h-4 w-4" /> Leave
                      </Button>
                    )}
                  </li>
                );
              })}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle className="text-base">Appearance</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex gap-2">
            {THEME_OPTIONS.map((opt) => {
              const Icon = opt.icon;
              const active = theme === opt.value;
              return (
                <Button
                  key={opt.value}
                  variant={active ? "default" : "outline"}
                  className={cn("flex-1 gap-2")}
                  onClick={() => setTheme(opt.value)}
                >
                  <Icon className="h-4 w-4" />
                  {opt.label}
                </Button>
              );
            })}
          </div>
        </CardContent>
      </Card>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle className="text-base">Session</CardTitle>
        </CardHeader>
        <CardContent>
          <Button
            variant="outline"
            onClick={() => {
              void signOut().then(() => navigate("/"));
            }}
          >
            <LogOut className="h-4 w-4" />
            Sign out
          </Button>
        </CardContent>
      </Card>

      <ConfirmDialog
        open={!!toLeave}
        onOpenChange={(o) => !o && setToLeave(null)}
        title={`Leave "${toLeave?.name}"?`}
        description="You'll lose access to this workspace. An admin can re-invite you later."
        destructive
        confirmLabel="Leave workspace"
        onConfirm={async () => {
          if (!toLeave) return;
          const membership = memberships.find((m) => m.workspaceId === toLeave.id);
          if (!membership) return;
          try {
            await leaveWorkspace(membership, toLeave.ownerId);
            // if we left the active workspace, switch to another
            if (activeWorkspaceId === toLeave.id) {
              const next = memberships.find((m) => m.workspaceId !== toLeave.id);
              if (next) switchWorkspace(next.workspaceId);
            }
            toast({ title: "Left workspace", variant: "success" });
          } catch (e) {
            toast({
              title: "Couldn't leave",
              description: e instanceof GuardrailError ? e.message : String(e),
              variant: "error",
            });
          }
        }}
      />
    </div>
  );
}
