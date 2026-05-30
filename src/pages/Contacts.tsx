// Contacts (§6.5). Searchable list; each row shows net position
// (green = owes you, red = you owe them).

import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { Plus, Pencil, Trash2 } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { createContact, deleteContact, updateContact } from "@/data/mutations";
import type { Contact, ContactType } from "@/types/models";
import { PageHeader } from "@/components/PageHeader";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Textarea } from "@/components/ui/textarea";
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
import { EmptyState, ErrorState, LoadingState } from "@/components/states";
import { useToast } from "@/components/ui/toast";
import { cn, formatMoney } from "@/lib/utils";

export function Contacts() {
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { contacts, positionOf, loading, error } = useData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const manage = can("contacts.manage");

  const [search, setSearch] = useState("");
  const [editing, setEditing] = useState<Contact | "new" | null>(null);
  const [toDelete, setToDelete] = useState<Contact | null>(null);

  const filtered = useMemo(
    () =>
      contacts
        .filter((c) => c.name.toLowerCase().includes(search.toLowerCase()))
        .sort((a, b) => a.name.localeCompare(b.name)),
    [contacts, search],
  );

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  return (
    <div>
      <PageHeader
        title="Contacts"
        description="People and businesses you transact with."
        actions={
          manage && (
            <Button onClick={() => setEditing("new")}>
              <Plus /> New contact
            </Button>
          )
        }
      />

      <Input
        placeholder="Search contacts…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="mb-4 max-w-sm"
      />

      {filtered.length === 0 ? (
        <EmptyState
          title={search ? "No matches" : "No contacts yet"}
          action={
            manage && !search && (
              <Button onClick={() => setEditing("new")}>New contact</Button>
            )
          }
        />
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Type</TableHead>
              <TableHead className="text-right">Net position</TableHead>
              {manage && <TableHead className="w-24" />}
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.map((c) => {
              const { net } = positionOf(c.id);
              return (
                <TableRow key={c.id}>
                  <TableCell className="font-medium">
                    <Link to={`/contacts/${c.id}`} className="hover:underline">
                      {c.name}
                    </Link>
                  </TableCell>
                  <TableCell>
                    <Badge variant="secondary">
                      {c.type === "business" ? "Business" : "Person"}
                    </Badge>
                  </TableCell>
                  <TableCell
                    className={cn(
                      "text-right tabular-nums font-medium",
                      net > 0 && "text-green-600",
                      net < 0 && "text-destructive",
                    )}
                  >
                    {net === 0
                      ? "—"
                      : net > 0
                        ? `${formatMoney(net, currency)} owes you`
                        : `${formatMoney(-net, currency)} you owe`}
                  </TableCell>
                  {manage && (
                    <TableCell>
                      <div className="flex justify-end gap-1">
                        <Button size="icon" variant="ghost" onClick={() => setEditing(c)}>
                          <Pencil />
                        </Button>
                        <Button size="icon" variant="ghost" onClick={() => setToDelete(c)}>
                          <Trash2 />
                        </Button>
                      </div>
                    </TableCell>
                  )}
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      )}

      {editing && activeWorkspaceId && (
        <ContactDialog
          workspaceId={activeWorkspaceId}
          contact={editing === "new" ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={() => toast({ title: "Contact saved", variant: "success" })}
        />
      )}

      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title={`Delete "${toDelete?.name}"?`}
        destructive
        confirmLabel="Delete"
        onConfirm={async () => {
          if (toDelete) {
            await deleteContact(toDelete.id);
            toast({ title: "Contact deleted", variant: "success" });
          }
        }}
      />
    </div>
  );
}

export function ContactDialog({
  workspaceId,
  contact,
  onClose,
  onSaved,
}: {
  workspaceId: string;
  contact: Contact | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(contact?.name ?? "");
  const [type, setType] = useState<ContactType>(contact?.type ?? "person");
  const [phone, setPhone] = useState(contact?.phone ?? "");
  const [email, setEmail] = useState(contact?.email ?? "");
  const [notes, setNotes] = useState(contact?.notes ?? "");
  const [busy, setBusy] = useState(false);

  async function save() {
    if (!name.trim()) return;
    setBusy(true);
    try {
      const data = {
        name: name.trim(),
        type,
        phone: phone.trim() || undefined,
        email: email.trim() || undefined,
        notes: notes.trim() || undefined,
      };
      if (contact) await updateContact(contact.id, data);
      else await createContact(workspaceId, data);
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
          <DialogTitle>{contact ? "Edit contact" : "New contact"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="c-name">Name</Label>
            <Input id="c-name" value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label>Type</Label>
            <Select value={type} onValueChange={(v) => setType(v as ContactType)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="person">Person</SelectItem>
                <SelectItem value="business">Business</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="c-phone">Phone</Label>
              <Input id="c-phone" value={phone} onChange={(e) => setPhone(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="c-email">Email</Label>
              <Input id="c-email" value={email} onChange={(e) => setEmail(e.target.value)} />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="c-notes">Notes</Label>
            <Textarea id="c-notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !name.trim()}>
            {busy ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
