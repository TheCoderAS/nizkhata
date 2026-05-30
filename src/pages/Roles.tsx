// Settings › Roles (§6.11). Create/edit/duplicate/delete; per-permission toggle
// editor; warns on dangerous perms; system roles are clone-only.

import { useState } from "react";
import { Plus, Copy, Pencil, Trash2, AlertTriangle, Lock } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useAdminData } from "@/data/useAdminData";
import {
  GuardrailError,
  createRole,
  deleteRole,
  duplicateRole,
  updateRole,
} from "@/data/adminMutations";
import type { Role } from "@/types/models";
import {
  DANGEROUS_PERMISSIONS,
  PERMISSIONS,
  type Permission,
  type PermissionMap,
} from "@/types/permissions";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { ErrorState, LoadingState } from "@/components/states";
import { useToast } from "@/components/ui/toast";
import { cn } from "@/lib/utils";

export function Roles() {
  const { activeWorkspaceId, can } = useWorkspace();
  const { roles, memberships, loading, error } = useAdminData();
  const { toast } = useToast();
  const manage = can("roles.manage");

  const [editing, setEditing] = useState<Role | "new" | null>(null);
  const [toDelete, setToDelete] = useState<Role | null>(null);

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  const counts = new Map<string, number>();
  for (const m of memberships) counts.set(m.roleId, (counts.get(m.roleId) ?? 0) + 1);

  return (
    <div>
      <PageHeader
        title="Roles"
        primaryAction={{
          label: "New role",
          icon: Plus,
          onClick: () => setEditing("new"),
          hidden: !manage,
        }}
      />

      <div className="grid gap-4 md:grid-cols-2">
        {roles
          .slice()
          .sort((a, b) => Number(b.isSystem) - Number(a.isSystem) || a.name.localeCompare(b.name))
          .map((role) => {
            const granted = PERMISSIONS.filter((p) => role.permissions[p]).length;
            return (
              <Card key={role.id}>
                <CardHeader className="flex-row items-center justify-between space-y-0">
                  <CardTitle className="flex items-center gap-2 text-base">
                    {role.name}
                    {role.isSystem && (
                      <Badge variant="outline">
                        <Lock className="mr-1 h-3 w-3" /> System
                      </Badge>
                    )}
                  </CardTitle>
                  {manage && (
                    <div className="flex gap-1">
                      <Button
                        size="icon"
                        variant="ghost"
                        title="Duplicate"
                        onClick={async () => {
                          if (activeWorkspaceId) {
                            await duplicateRole(activeWorkspaceId, role);
                            toast({ title: "Role duplicated", variant: "success" });
                          }
                        }}
                      >
                        <Copy />
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        title={role.isSystem ? "System roles are read-only" : "Edit"}
                        disabled={role.isSystem}
                        onClick={() => setEditing(role)}
                      >
                        <Pencil />
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        title="Delete"
                        disabled={role.isSystem}
                        onClick={() => setToDelete(role)}
                      >
                        <Trash2 />
                      </Button>
                    </div>
                  )}
                </CardHeader>
                <CardContent className="text-sm text-muted-foreground">
                  {granted} / {PERMISSIONS.length} permissions ·{" "}
                  {counts.get(role.id) ?? 0} member(s)
                </CardContent>
              </Card>
            );
          })}
      </div>

      {editing && activeWorkspaceId && (
        <RoleEditor
          workspaceId={activeWorkspaceId}
          role={editing === "new" ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={() => toast({ title: "Role saved", variant: "success" })}
        />
      )}

      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title={`Delete "${toDelete?.name}"?`}
        destructive
        confirmLabel="Delete"
        onConfirm={async () => {
          if (!toDelete) return;
          try {
            await deleteRole(toDelete, memberships);
            toast({ title: "Role deleted", variant: "success" });
          } catch (e) {
            toast({
              title: "Couldn't delete",
              description: e instanceof GuardrailError ? e.message : String(e),
              variant: "error",
            });
          }
        }}
      />
    </div>
  );
}

const PERMISSION_GROUPS: { label: string; prefix: string }[] = [
  { label: "Transactions", prefix: "transactions." },
  { label: "Accounts", prefix: "accounts." },
  { label: "Categories", prefix: "categories." },
  { label: "Contacts", prefix: "contacts." },
  { label: "Debts", prefix: "debts." },
  { label: "Dues", prefix: "dues." },
  { label: "Reports", prefix: "reports." },
  { label: "Members", prefix: "members." },
  { label: "Roles", prefix: "roles." },
  { label: "Workspace", prefix: "workspace." },
];

function RoleEditor({
  workspaceId,
  role,
  onClose,
  onSaved,
}: {
  workspaceId: string;
  role: Role | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(role?.name ?? "");
  const [perms, setPerms] = useState<PermissionMap>({ ...(role?.permissions ?? {}) });
  const [busy, setBusy] = useState(false);

  function toggle(p: Permission) {
    setPerms((prev) => ({ ...prev, [p]: !prev[p] }));
  }

  async function save() {
    if (!name.trim()) return;
    setBusy(true);
    try {
      if (role) await updateRole(role.id, { name: name.trim(), permissions: perms });
      else await createRole(workspaceId, name.trim(), perms);
      onSaved();
      onClose();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>{role ? "Edit role" : "New role"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-1.5">
          <Label htmlFor="role-name">Name</Label>
          <Input id="role-name" value={name} onChange={(e) => setName(e.target.value)} />
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          {PERMISSION_GROUPS.map((group) => (
            <div key={group.prefix}>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                {group.label}
              </p>
              <div className="space-y-1">
                {PERMISSIONS.filter((p) => p.startsWith(group.prefix)).map((p) => {
                  const dangerous = DANGEROUS_PERMISSIONS.includes(p);
                  return (
                    <label
                      key={p}
                      className={cn(
                        "flex items-center gap-2 rounded px-2 py-1 text-sm hover:bg-muted",
                        dangerous && perms[p] && "bg-amber-50",
                      )}
                    >
                      <input
                        type="checkbox"
                        checked={!!perms[p]}
                        onChange={() => toggle(p)}
                      />
                      <span>{p.split(".")[1]}</span>
                      {dangerous && (
                        <AlertTriangle className="h-3 w-3 text-amber-500" />
                      )}
                    </label>
                  );
                })}
              </div>
            </div>
          ))}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !name.trim()}>
            {busy ? "Saving…" : "Save role"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
