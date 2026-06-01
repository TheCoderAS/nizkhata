// Contact detail (§6.5). Header (net, total in/out) + tabs:
// Transactions | Debts | Report. Debts grouped by purpose.

import { useMemo } from "react";
import { Link, useParams } from "react-router-dom";
import { ArrowLeft, ArrowDownLeft, ArrowUpRight, ArrowLeftRight, Scale } from "lucide-react";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { useData } from "@/data/WorkspaceDataProvider";
import { txnsByContact } from "@/lib/links";
import type { DebtPurpose } from "@/types/models";
import { ContactChat } from "@/components/ContactChat";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { EmptyState, ErrorState, PageSkeleton } from "@/components/states";
import { cn, formatMoney } from "@/lib/utils";

const PURPOSE_LABELS: Record<DebtPurpose, string> = {
  loan: "Loans",
  custodial_savings: "Custodial savings",
  lending: "Lendings",
  reimbursable: "Reimbursable",
  informal: "Informal",
  shared: "Shared",
};

export function ContactDetail() {
  const { contactId } = useParams<{ contactId: string }>();
  const { activeWorkspace, can } = useWorkspace();
  const { contacts, transactions, debts, positionOf, outstandingOf, loading, error } =
    useData();
  const currency = activeWorkspace?.baseCurrency ?? "INR";
  const canViewTxns = can("transactions.view");

  const contact = contacts.find((c) => c.id === contactId);
  const position = useMemo(
    () => (contactId ? positionOf(contactId) : null),
    [contactId, positionOf],
  );

  if (loading) return <PageSkeleton />;
  if (error) return <ErrorState message={error} />;
  if (!contact || !position)
    return <EmptyState title="Contact not found" />;

  const contactTxns = transactions.filter((t) => t.contactId === contactId);
  const contactDebts = debts.filter((d) => d.contactId === contactId);
  const debtsByPurpose = new Map<DebtPurpose, typeof contactDebts>();
  for (const d of contactDebts) {
    const arr = debtsByPurpose.get(d.purpose) ?? [];
    arr.push(d);
    debtsByPurpose.set(d.purpose, arr);
  }

  return (
    <div>
      <Link to="/contacts" className="mb-2 inline-flex items-center gap-1 text-sm text-muted-foreground hover:underline">
        <ArrowLeft className="h-4 w-4" /> Contacts
      </Link>
      <div className="mb-2 flex flex-wrap items-center gap-2">
        <h1 className="text-2xl font-semibold tracking-tight">{contact.name}</h1>
        <Badge variant="secondary">
          {contact.type === "business" ? "Business" : "Person"}
        </Badge>
        {contact.relationship === "family" && <Badge variant="outline">Family</Badge>}
      </div>
      {(() => {
        const emails =
          contact.emails && contact.emails.length > 0
            ? contact.emails.map((e) => e.value)
            : contact.email
              ? [contact.email]
              : [];
        const bits = [contact.phone, ...emails, contact.address].filter(Boolean);
        return bits.length > 0 ? (
          <p className="mb-6 text-sm text-muted-foreground">{bits.join(" · ")}</p>
        ) : (
          <div className="mb-6" />
        );
      })()}

      <div className="mb-6 grid grid-cols-3 gap-3">
        <Card>
          <CardHeader className="flex-row items-center justify-between space-y-0 pb-1">
            <CardTitle className="text-xs font-normal text-muted-foreground">Net</CardTitle>
            <Scale className="h-3.5 w-3.5 text-muted-foreground" />
          </CardHeader>
          <CardContent
            className={cn(
              "truncate font-strong text-sm tabular-nums sm:text-lg",
              position.net > 0 && "text-green-600",
              position.net < 0 && "text-destructive",
            )}
          >
            {position.net === 0 ? "—" : formatMoney(position.net, currency)}
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex-row items-center justify-between space-y-0 pb-1">
            <CardTitle className="text-xs font-normal text-muted-foreground">In</CardTitle>
            <ArrowDownLeft className="h-3.5 w-3.5 text-green-600" />
          </CardHeader>
          <CardContent className="truncate font-strong text-sm tabular-nums text-green-600 sm:text-lg">
            {formatMoney(position.totalIn, currency)}
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex-row items-center justify-between space-y-0 pb-1">
            <CardTitle className="text-xs font-normal text-muted-foreground">Out</CardTitle>
            <ArrowUpRight className="h-3.5 w-3.5 text-destructive" />
          </CardHeader>
          <CardContent className="truncate font-strong text-sm tabular-nums text-destructive sm:text-lg">
            {formatMoney(position.totalOut, currency)}
          </CardContent>
        </Card>
      </div>

      <Tabs defaultValue="transactions">
        <div className="flex items-center justify-between gap-2">
          <TabsList>
            <TabsTrigger value="transactions">Transactions</TabsTrigger>
            <TabsTrigger value="debts">Debts</TabsTrigger>
            <TabsTrigger value="report">Report</TabsTrigger>
          </TabsList>
          {canViewTxns && contactId && (
            <Button variant="outline" size="sm" asChild>
              <Link to={txnsByContact(contactId)}>
                <ArrowLeftRight className="h-4 w-4" />
                <span className="hidden sm:inline">Open in Transactions</span>
              </Link>
            </Button>
          )}
        </div>

        <TabsContent value="transactions">
          {contactId && <ContactChat contactId={contactId} />}
        </TabsContent>

        <TabsContent value="debts">
          {contactDebts.length === 0 ? (
            <EmptyState title="No debts with this contact" />
          ) : (
            <div className="space-y-6">
              {[...debtsByPurpose.entries()].map(([purpose, list]) => (
                <div key={purpose}>
                  <h3 className="mb-2 text-sm font-semibold">{PURPOSE_LABELS[purpose]}</h3>
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Label</TableHead>
                        <TableHead>Direction</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead className="text-right">Outstanding</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {list.map((d) => (
                        <TableRow key={d.id}>
                          <TableCell className="font-medium">{d.label ?? "—"}</TableCell>
                          <TableCell>
                            <Badge variant={d.direction === "owed" ? "success" : "warning"}>
                              {d.direction === "owed" ? "They owe you" : "You owe"}
                            </Badge>
                          </TableCell>
                          <TableCell>
                            <Badge variant={d.status === "open" ? "secondary" : "outline"}>
                              {d.status}
                            </Badge>
                          </TableCell>
                          <TableCell className="text-right tabular-nums">
                            {formatMoney(outstandingOf(d.id), currency)}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              ))}
            </div>
          )}
        </TabsContent>

        <TabsContent value="report">
          <Card>
            <CardContent className="space-y-2 pt-6 text-sm">
              <Row label="Transactions" value={String(contactTxns.length)} />
              <Row label="Total received" value={formatMoney(position.totalIn, currency)} />
              <Row label="Total paid" value={formatMoney(position.totalOut, currency)} />
              <Row
                label="Open debts"
                value={String(contactDebts.filter((d) => d.status === "open").length)}
              />
              <Row
                label="Net position"
                value={formatMoney(position.net, currency)}
              />
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between border-b py-1 last:border-0">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium tabular-nums">{value}</span>
    </div>
  );
}
