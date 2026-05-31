// Contacts (§6.5). Searchable list; each row shows net position
// (green = owes you, red = you owe them).

import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Plus, Pencil, Trash2, X } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { createContact, deleteContact, updateContact } from "@/data/mutations";
import type {
  Contact,
  ContactType,
  ContactEmail,
  ContactRelationship,
} from "@/types/models";
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

const RELATIONSHIP_LABELS: Record<ContactRelationship, string> = {
  external: "External",
  family: "Family",
};

const EMAIL_LABEL_OPTIONS = ["Personal", "Work", "Other"];

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
    () =>
      contacts.filter(
        // Hide shared-ledger handles — they live in the Shared section.
        (c) => !c.connectionUid && c.name.toLowerCase().includes(search.toLowerCase()),
      ),
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
                    <TableCell>
                      <span className="flex items-center gap-2">
                        <span className="truncate">{c.name}</span>
                        {c.relationship === "family" && (
                          <Badge variant="outline" className="shrink-0 text-[10px]">
                            Family
                          </Badge>
                        )}
                      </span>
                    </TableCell>
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
  const [relationship, setRelationship] = useState<ContactRelationship>(
    contact?.relationship ?? "external",
  );
  const [phone, setPhone] = useState(contact?.phone ?? "");
  const [address, setAddress] = useState(contact?.address ?? "");
  const [notes, setNotes] = useState(contact?.notes ?? "");
  const [emails, setEmails] = useState<Array<ContactEmail & { key: string }>>(() => {
    const seed =
      contact?.emails && contact.emails.length > 0
        ? contact.emails
        : contact?.email
          ? [{ label: "Personal", value: contact.email }]
          : [];
    return seed.map((e, i) => ({ ...e, key: `${i}` }));
  });
  const [busy, setBusy] = useState(false);

  function addEmail() {
    setEmails((prev) => [...prev, { key: `${Date.now()}`, label: EMAIL_LABEL_OPTIONS[0], value: "" }]);
  }
  function patchEmail(key: string, patch: Partial<ContactEmail>) {
    setEmails((prev) => prev.map((e) => (e.key === key ? { ...e, ...patch } : e)));
  }
  function removeEmail(key: string) {
    setEmails((prev) => prev.filter((e) => e.key !== key));
  }

  async function save() {
    if (!name.trim()) return;
    setBusy(true);
    try {
      const cleanEmails: ContactEmail[] = emails
        .map((e) => ({ label: e.label.trim() || "Other", value: e.value.trim() }))
        .filter((e) => e.value);
      const data = {
        name: name.trim(),
        type,
        relationship,
        phone: phone.trim() || undefined,
        address: address.trim() || undefined,
        notes: notes.trim() || undefined,
        emails: cleanEmails.length > 0 ? cleanEmails : undefined,
        // keep legacy single email in sync for back-compat readers
        email: cleanEmails[0]?.value,
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
      <DialogContent className="max-h-[90vh] max-w-md overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{contact ? "Edit contact" : "New contact"}</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="c-name">Name</Label>
            <Input id="c-name" value={name} onChange={(e) => setName(e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-3">
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
            <div className="space-y-1.5">
              <Label>Relationship</Label>
              <Select
                value={relationship}
                onValueChange={(v) => setRelationship(v as ContactRelationship)}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(Object.keys(RELATIONSHIP_LABELS) as ContactRelationship[]).map((r) => (
                    <SelectItem key={r} value={r}>
                      {RELATIONSHIP_LABELS[r]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="c-phone">Phone</Label>
            <Input id="c-phone" value={phone} onChange={(e) => setPhone(e.target.value)} />
          </div>

          {/* Emails — multiple, each with a label */}
          <div className="space-y-1.5">
            <div className="flex items-center justify-between">
              <Label>Emails</Label>
              <Button
                type="button"
                size="sm"
                variant="ghost"
                className="h-7 px-2 text-xs"
                onClick={addEmail}
              >
                <Plus className="mr-1 h-3 w-3" /> Add
              </Button>
            </div>
            {emails.length === 0 ? (
              <p className="text-xs text-muted-foreground">No emails added.</p>
            ) : (
              <div className="space-y-2">
                {emails.map((e) => (
                  <div key={e.key} className="flex items-center gap-2">
                    <Select value={e.label} onValueChange={(v) => patchEmail(e.key, { label: v })}>
                      <SelectTrigger className="w-28 shrink-0">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {EMAIL_LABEL_OPTIONS.map((opt) => (
                          <SelectItem key={opt} value={opt}>
                            {opt}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <Input
                      type="email"
                      placeholder="name@example.com"
                      value={e.value}
                      onChange={(ev) => patchEmail(e.key, { value: ev.target.value })}
                    />
                    <button
                      type="button"
                      onClick={() => removeEmail(e.key)}
                      aria-label="Remove email"
                      className="shrink-0 rounded p-1.5 text-muted-foreground hover:bg-accent hover:text-destructive"
                    >
                      <X className="h-4 w-4" />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="c-address">Address</Label>
            <Textarea id="c-address" rows={2} value={address} onChange={(e) => setAddress(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="c-notes">Notes</Label>
            <Textarea id="c-notes" rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
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
