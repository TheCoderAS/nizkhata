// Settings › Workspace (§6.12). Name, currency, FY start month; delete (owner only).

import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "@/auth/AuthProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { deleteWorkspace, updateWorkspace } from "@/data/mutations";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ConfirmDialog } from "@/components/ConfirmDialog";
import { PageSkeleton } from "@/components/states";
import { useToast } from "@/components/ui/toast";

const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

const CURRENCIES = ["INR", "USD", "EUR", "GBP", "AED", "SGD", "AUD", "CAD"];

export function WorkspaceSettings() {
  const navigate = useNavigate();
  const { firebaseUser } = useAuth();
  const { activeWorkspace, can } = useWorkspace();
  const { toast } = useToast();

  const [name, setName] = useState(activeWorkspace?.name ?? "");
  const [currency, setCurrency] = useState(activeWorkspace?.baseCurrency ?? "INR");
  const [fyStartMonth, setFyStartMonth] = useState(String(activeWorkspace?.fyStartMonth ?? 4));
  const [busy, setBusy] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

  if (!activeWorkspace) return <PageSkeleton />;

  const isOwner = firebaseUser?.uid === activeWorkspace.ownerId;
  const canDelete = isOwner && can("workspace.delete");

  async function save() {
    if (!activeWorkspace) return;
    setBusy(true);
    try {
      await updateWorkspace(activeWorkspace.id, {
        name: name.trim(),
        baseCurrency: currency,
        fyStartMonth: Number(fyStartMonth),
      });
      toast({ title: "Workspace updated", variant: "success" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="max-w-xl">
      <PageHeader title="Workspace" />

      <Card>
        <CardHeader>
          <CardTitle className="text-base">General</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-1.5">
            <Label>Name</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>Base currency</Label>
              <Select value={currency} onValueChange={setCurrency}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {CURRENCIES.map((c) => (
                    <SelectItem key={c} value={c}>
                      {c}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>FY start month</Label>
              <Select value={fyStartMonth} onValueChange={setFyStartMonth}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {MONTHS.map((m, i) => (
                    <SelectItem key={m} value={String(i + 1)}>
                      {m}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <Button onClick={() => void save()} disabled={busy || !name.trim()}>
            {busy ? "Saving…" : "Save changes"}
          </Button>
        </CardContent>
      </Card>

      {canDelete && (
        <Card className="mt-6 border-destructive/40">
          <CardHeader>
            <CardTitle className="text-base text-destructive">Danger zone</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-sm text-muted-foreground">
              Deleting a workspace removes it for everyone. This cannot be undone.
            </p>
            <Button variant="destructive" onClick={() => setConfirmDelete(true)}>
              Delete workspace
            </Button>
          </CardContent>
        </Card>
      )}

      <ConfirmDialog
        open={confirmDelete}
        onOpenChange={setConfirmDelete}
        title={`Delete "${activeWorkspace.name}"?`}
        description="This permanently removes the workspace. Member, role and transaction documents are not auto-deleted by the client; remove them separately if required."
        destructive
        confirmLabel="Delete workspace"
        onConfirm={async () => {
          if (!firebaseUser) return;
          await deleteWorkspace(activeWorkspace.id, firebaseUser.uid);
          toast({ title: "Workspace deleted", variant: "success" });
          // The active workspace is gone; the provider will self-heal the
          // selection to another membership. Send the user home meanwhile.
          navigate("/dashboard");
        }}
      />
    </div>
  );
}
