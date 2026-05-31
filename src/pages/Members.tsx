// Settings › Members (§6.10). List members + roles; invite; change role; remove
// (owner protected). Note: per Security Rules a member can only read their own
// users/{uid} profile, so other members are shown by uid + their role.

import { useState } from "react";
import { Plus, Trash2, Mail, Ban } from "lucide-react";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useAdminData } from "@/data/useAdminData";
import {
  GuardrailError,
  changeMemberRole,
  createInvite,
  removeMember,
  revokeInvite,
} from "@/data/adminMutations";
import type { Membership, Role } from "@/types/models";
import { PageHeader } from "@/components/PageHeader";
import { RowActions } from "@/components/RowActions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { ErrorState, PageSkeleton } from "@/components/states";
import { useToast } from "@/components/ui/toast";

/**
 * Best display label for a member: denormalized name, then email, then a short
 * uid fallback (older memberships created before identity was stored).
 */
function memberLabel(m: Membership): string {
  return m.displayName || m.email || `${m.uid.slice(0, 8)}…`;
}

/** The reserved Owner role — the seeded system role named "Owner". */
function isOwnerRole(r: Role): boolean {
  return r.isSystem && r.name === "Owner";
}

export function Members() {
  const { firebaseUser } = useAuth();
  const { activeWorkspace, can } = useWorkspace();
  const { memberships, roles, rolesById, invites, loading, error } = useAdminData();
  const { toast } = useToast();

  const canInvite = can("members.invite");
  const canRemove = can("members.remove");
  const ownerId = activeWorkspace?.ownerId;

  const [inviteOpen, setInviteOpen] = useState(false);
  const [toRemove, setToRemove] = useState<Membership | null>(null);

  if (loading) return <PageSkeleton />;
  if (error) return <ErrorState message={error} />;

  const pendingInvites = invites.filter((i) => i.status === "pending");
  // The Owner role is reserved for the workspace owner — never assignable to
  // anyone else (the single owner is workspace.ownerId, fixed at creation).
  const assignableRoles = roles.filter((r) => !isOwnerRole(r));

  async function handleRoleChange(m: Membership, roleId: string) {
    const role = rolesById[roleId];
    if (!role) return;
    try {
      await changeMemberRole(m, role, ownerId ?? "");
      toast({ title: "Role updated", variant: "success" });
    } catch (e) {
      toast({
        title: "Couldn't change role",
        description: e instanceof GuardrailError ? e.message : String(e),
        variant: "error",
      });
    }
  }

  return (
    <div>
      <PageHeader
        title="Members"
        primaryAction={{
          label: "Invite",
          icon: Plus,
          onClick: () => setInviteOpen(true),
          hidden: !canInvite,
        }}
      />

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Member</TableHead>
            <TableHead>Role</TableHead>
            <TableHead>Status</TableHead>
            {canRemove && <TableHead className="w-20" />}
          </TableRow>
        </TableHeader>
        <TableBody>
          {memberships.map((m) => {
            const isOwner = m.uid === ownerId;
            const isSelf = m.uid === firebaseUser?.uid;
            return (
              <TableRow key={m.id}>
                <TableCell className="font-medium">
                  <div className="flex flex-col">
                    <span>
                      {isSelf ? "You" : memberLabel(m)}
                      {isOwner && (
                        <Badge variant="outline" className="ml-2">
                          Owner
                        </Badge>
                      )}
                    </span>
                    {!isSelf && m.displayName && m.email && (
                      <span className="text-xs text-muted-foreground">{m.email}</span>
                    )}
                  </div>
                </TableCell>
                <TableCell>
                  {canInvite && !isOwner ? (
                    <Select value={m.roleId} onValueChange={(v) => handleRoleChange(m, v)}>
                      <SelectTrigger className="w-40">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {assignableRoles.map((r) => (
                          <SelectItem key={r.id} value={r.id}>
                            {r.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  ) : (
                    <Badge variant="secondary">{rolesById[m.roleId]?.name ?? "—"}</Badge>
                  )}
                </TableCell>
                <TableCell>
                  <Badge variant="success">active</Badge>
                </TableCell>
                {canRemove && (
                  <TableCell>
                    {!isOwner && (
                      <RowActions
                        actions={[
                          {
                            label: "Remove member",
                            icon: Trash2,
                            destructive: true,
                            onSelect: () => setToRemove(m),
                          },
                        ]}
                      />
                    )}
                  </TableCell>
                )}
              </TableRow>
            );
          })}
        </TableBody>
      </Table>

      {pendingInvites.length > 0 && (
        <div className="mt-8">
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Pending invites
          </h2>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Email</TableHead>
                <TableHead>Role</TableHead>
                {canInvite && <TableHead className="w-20" />}
              </TableRow>
            </TableHeader>
            <TableBody>
              {pendingInvites.map((i) => (
                <TableRow key={i.id}>
                  <TableCell className="font-medium">
                    <Mail className="mr-1 inline h-3 w-3" /> {i.email}
                  </TableCell>
                  <TableCell>{rolesById[i.roleId]?.name ?? "—"}</TableCell>
                  {canInvite && (
                    <TableCell>
                      <RowActions
                        actions={[
                          {
                            label: "Revoke invite",
                            icon: Ban,
                            destructive: true,
                            onSelect: async () => {
                              await revokeInvite(i.id);
                              toast({ title: "Invite revoked", variant: "success" });
                            },
                          },
                        ]}
                      />
                    </TableCell>
                  )}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      {inviteOpen && activeWorkspace && (
        <InviteDialog
          workspaceId={activeWorkspace.id}
          invitedBy={firebaseUser?.uid ?? ""}
          roles={assignableRoles}
          onClose={() => setInviteOpen(false)}
          onSaved={() => toast({ title: "Invite sent", variant: "success" })}
        />
      )}

      <ConfirmDialog
        open={!!toRemove}
        onOpenChange={(o) => !o && setToRemove(null)}
        title="Remove member?"
        description="They will lose access to this workspace."
        destructive
        confirmLabel="Remove"
        onConfirm={async () => {
          if (toRemove) {
            try {
              await removeMember(toRemove, ownerId ?? "");
              toast({ title: "Member removed", variant: "success" });
            } catch (e) {
              toast({
                title: "Couldn't remove",
                description: e instanceof GuardrailError ? e.message : String(e),
                variant: "error",
              });
            }
          }
        }}
      />
    </div>
  );
}

function InviteDialog({
  workspaceId,
  invitedBy,
  roles,
  onClose,
  onSaved,
}: {
  workspaceId: string;
  invitedBy: string;
  roles: { id: string; name: string }[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [email, setEmail] = useState("");
  const [roleId, setRoleId] = useState(roles[0]?.id ?? "");
  const [busy, setBusy] = useState(false);

  async function save() {
    if (!email.trim() || !roleId) return;
    setBusy(true);
    try {
      await createInvite(workspaceId, email.trim(), roleId, invitedBy);
      onSaved();
      onClose();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Invite member</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="inv-email">Email</Label>
            <Input
              id="inv-email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="person@example.com"
            />
            <p className="text-xs text-muted-foreground">
              They'll join with this role on their next sign-in.
            </p>
          </div>
          <div className="space-y-1.5">
            <Label>Role</Label>
            <Select value={roleId} onValueChange={setRoleId}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {roles.map((r) => (
                  <SelectItem key={r.id} value={r.id}>
                    {r.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !email.trim()}>
            {busy ? "Sending…" : "Send invite"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
