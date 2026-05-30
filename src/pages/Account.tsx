// Settings › Account — the signed-in user's personal profile + preferences.
// Profile fields come from the Google identity (read-only); theme is editable
// here too (mirrors the avatar menu).

import { LogOut, Sun, Moon, Laptop } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useTheme, type Theme } from "@/theme/ThemeProvider";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

const THEME_OPTIONS: { value: Theme; label: string; icon: typeof Sun }[] = [
  { value: "light", label: "Light", icon: Sun },
  { value: "dark", label: "Dark", icon: Moon },
  { value: "system", label: "System", icon: Laptop },
];

export function Account() {
  const { firebaseUser, signOut } = useAuth();
  const { theme, setTheme } = useTheme();
  const { memberships } = useWorkspace();

  return (
    <div className="max-w-xl">
      <PageHeader title="Account" />

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
              <p className="truncate font-medium">
                {firebaseUser?.displayName ?? "—"}
              </p>
              <p className="truncate text-sm text-muted-foreground">
                {firebaseUser?.email}
              </p>
            </div>
          </div>
          <div className="flex items-center justify-between border-t pt-3 text-sm">
            <span className="text-muted-foreground">Workspaces</span>
            <Badge variant="secondary">{memberships.length}</Badge>
          </div>
          <p className="text-xs text-muted-foreground">
            Your name, email and photo come from your Google account.
          </p>
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
          <Button variant="outline" onClick={() => void signOut()}>
            <LogOut className="h-4 w-4" />
            Sign out
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
