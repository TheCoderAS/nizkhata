// Contacts (§6.5). Searchable list; each row shows net position
// (green = owes you, red = you owe them).

import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Plus, Pencil, Trash2 } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { createContact, deleteContact, updateContact } from "@/data/mutations";
import type { Contact, ContactType } from "@/types/models";
import { PageHeader } from "@/components/PageHeader";
import { RowActions, type RowAction } from "@/components/RowActions";
import { SortableHead } from "@/components/SortableHead";
import { ColumnsMenu } from "@/components/ColumnsMenu";
import { Toolbar } from "@/components/Toolbar";
import { useColumnPrefs, type ColumnDef } from "@/lib/useColumnPrefs";
import { useSort, type SortAccessor } from "@/lib/useSort";
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

type SortKey = "name" | "type" | "net";
type ColKey = "name" | "type" | "net";

const COLUMNS: ColumnDef<ColKey>[] = [
  { key: "name", label: "Name", defaultVisible: true, locked: true },
  { key: "type", label: "Type", defaultVisible: true },
  { key: "net", label: "Net position", defaultVisible: true },
];

export function Contacts() {
  const navigate = useNavigate();
  const { activeWorkspaceId, activeWorkspace, can } = useWorkspace();
  const { contacts, positionOf, loading, error } = useData();
  const { toast } = useToast();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const manage = can("contacts.manage");

  const [search, setSearch] = useState("");
  const [editing, setEditing] = useState<Contact | "new" | null>(null);
  const [toDelete, setToDelete] = useState<Contact | null>(null);

  const filtered = useMemo(
    () => contacts.filter((c) => c.name.toLowerCase().includes(search.toLowerCase())),
    [contacts, search],
  );

  const cols = useColumnPrefs<ColKey>("contacts", COLUMNS);

  const accessors: Record<SortKey, SortAccessor<Contact>> = {
    name: (c) => c.name,
    type: (c) => c.type,
    net: (c) => positionOf(c.id).net,
  };
  const { sorted, sort, toggle } = useSort(filtered, accessors, {
    key: "name",
    direction: "asc",
  });

  if (loading) return <LoadingState />;
  if (error) return <ErrorState message={error} />;

  function rowActions(c: Contact): RowAction[] {
    return [
      { label: "Edit", icon: Pencil, onSelect: () => setEditing(c), hidden: !manage },
      {
        label: "Delete",
        icon: Trash2,
        onSelect: () => setToDelete(c),
        destructive: true,
        separatorBefore: true,
        hidden: !manage,
      },
    ];
  }

  return (
    <div>
      <PageHeader
        title="Contacts"
        primaryAction={{
          label: "New contact",
          icon: Plus,
          onClick: () => setEditing("new"),
          hidden: !manage,
        }}
      />

      <Toolbar search={search} onSearch={setSearch} placeholder="Search contacts…">
        <ColumnsMenu columns={cols.columns} isVisible={cols.isVisible} toggle={cols.toggle} reset={cols.reset} />
      </Toolbar>

      {sorted.length === 0 ? (
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
              {cols.isVisible("name") && (
                <SortableHead sortKey="name" sort={sort} onToggle={toggle}>
                  Name
                </SortableHead>
              )}
              {cols.isVisible("type") && (
                <SortableHead sortKey="type" sort={sort} onToggle={toggle}>
                  Type
                </SortableHead>
              )}
              {cols.isVisible("net") && (
                <SortableHead sortKey="net" sort={sort} onToggle={toggle} className="text-right">
                  Net position
                </SortableHead>
              )}
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {sorted.map((c) => {
              const { net } = positionOf(c.id);
              return (
                <TableRow
                  key={c.id}
                  onClick={() => navigate(`/contacts/${c.id}`)}
                  className="cursor-pointer"
                >
                  {cols.isVisible("name") && (
                    <TableCell className="font-medium">{c.name}</TableCell>
                  )}
                  {cols.isVisible("type") && (
                    <TableCell>
                      <Badge variant="secondary">
                        {c.type === "business" ? "Business" : "Person"}
                      </Badge>
                    </TableCell>
                  )}
                  {cols.isVisible("net") && (
                    <TableCell
                      className={cn(
                        "text-right tabular-nums font-medium",
                        net > 0 && "text-green-600",
                        net < 0 && "text-destructive",
                      )}
                    >
                      {net === 0 ? "—" : formatMoney(net, currency)}
                    </TableCell>
                  )}
                  <TableCell>
                    <RowActions actions={rowActions(c)} />
                  </TableCell>
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
