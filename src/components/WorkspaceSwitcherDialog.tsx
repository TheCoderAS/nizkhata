// Switch-workspace modal (req): searchable, name-sorted list of the user's
// workspaces with an inline "create workspace" flow. Opened from the avatar menu.

import { useMemo, useState } from "react";
import { Check, Plus, Search, Loader2 } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { createWorkspace } from "@/workspace/onboarding";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/components/ui/toast";
import { cn } from "@/lib/utils";

export function WorkspaceSwitcherDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const { firebaseUser } = useAuth();
  const { workspaces, activeWorkspaceId, switchWorkspace } = useWorkspace();
  const { toast } = useToast();

  const [search, setSearch] = useState("");
  const [creating, setCreating] = useState(false);
  const [newName, setNewName] = useState("");
  const [busy, setBusy] = useState(false);

  const filtered = useMemo(
    () =>
      workspaces
        .filter((w) => w.name.toLowerCase().includes(search.toLowerCase()))
        .sort((a, b) => a.name.localeCompare(b.name)),
    [workspaces, search],
  );

  function pick(id: string) {
    switchWorkspace(id);
    onOpenChange(false);
  }

  async function create() {
    if (!firebaseUser || !newName.trim()) return;
    setBusy(true);
    try {
      const id = await createWorkspace(firebaseUser, newName.trim());
      toast({ title: "Workspace created", variant: "success" });
      // membership listener will pick it up; switch once it's selectable
      switchWorkspace(id);
      setNewName("");
      setCreating(false);
      onOpenChange(false);
    } catch (e) {
      toast({
        title: "Couldn't create workspace",
        description: e instanceof Error ? e.message : String(e),
        variant: "error",
      });
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Switch workspace</DialogTitle>
          <DialogDescription>
            Choose a workspace, or create a new one.
          </DialogDescription>
        </DialogHeader>

        {!creating ? (
          <>
            <div className="relative">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                autoFocus
                placeholder="Search workspaces…"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="pl-9"
              />
            </div>

            <div className="-mx-1 max-h-72 space-y-1 overflow-y-auto px-1">
              {filtered.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">
                  No workspaces match “{search}”.
                </p>
              ) : (
                filtered.map((w) => {
                  const active = w.id === activeWorkspaceId;
                  return (
                    <button
                      key={w.id}
                      onClick={() => pick(w.id)}
                      className={cn(
                        "flex w-full items-center gap-3 rounded-lg border px-3 py-2.5 text-left text-sm transition-colors hover:bg-accent",
                        active ? "border-primary bg-accent" : "border-transparent",
                      )}
                    >
                      <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-primary text-xs font-semibold text-primary-foreground">
                        {w.name.slice(0, 2).toUpperCase()}
                      </span>
                      <span className="min-w-0 flex-1 truncate font-medium">{w.name}</span>
                      {active && <Check className="h-4 w-4 shrink-0 text-primary" />}
                    </button>
                  );
                })
              )}
            </div>

            <DialogFooter>
              <Button variant="outline" className="w-full" onClick={() => setCreating(true)}>
                <Plus className="h-4 w-4" /> New workspace
              </Button>
            </DialogFooter>
          </>
        ) : (
          <>
            <div className="space-y-1.5">
              <label className="text-sm font-medium" htmlFor="ws-name">
                Workspace name
              </label>
              <Input
                id="ws-name"
                autoFocus
                placeholder="e.g. Family budget"
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && void create()}
              />
              <p className="text-xs text-muted-foreground">
                You'll be the owner, with default roles and categories seeded.
              </p>
            </div>
            <DialogFooter>
              <Button
                variant="outline"
                onClick={() => setCreating(false)}
                disabled={busy}
              >
                Back
              </Button>
              <Button onClick={() => void create()} disabled={busy || !newName.trim()}>
                {busy ? (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin" /> Creating…
                  </>
                ) : (
                  "Create workspace"
                )}
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}
