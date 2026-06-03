// Global ⌘K / Ctrl+K command palette: fuzzy-ish search across navigation
// destinations and the workspace's contacts, accounts, categories and recent
// transactions, with keyboard navigation. Selecting an item routes to it
// (entities deep-link to their filtered/opened views via lib/links).

import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  Search,
  LayoutDashboard,
  ArrowLeftRight,
  Users,
  Wallet,
  Tags,
  HandCoins,
  CalendarClock,
  Split,
  BarChart3,
  type LucideIcon,
} from "lucide-react";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { useData } from "@/data/WorkspaceDataProvider";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { txnsByCategory, txnsByContact, accountLedgerPath } from "@/lib/links";
import type { Permission } from "@/types/permissions";
import { cn } from "@/lib/utils";

interface Item {
  id: string;
  label: string;
  hint?: string;
  icon: LucideIcon;
  to: string;
  group: string;
}

export function CommandPalette({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const navigate = useNavigate();
  const { can } = useWorkspace();
  const { contacts, accounts, categories } = useData();
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  // Build the searchable index (nav + entities), permission-gated.
  const items = useMemo<Item[]>(() => {
    const out: Item[] = [];
    const navDest: Array<[string, string, LucideIcon, Permission | undefined]> = [
      ["Dashboard", "/dashboard", LayoutDashboard, undefined],
      ["Transactions", "/transactions", ArrowLeftRight, "transactions.view"],
      ["Dues", "/dues", CalendarClock, "dues.view"],
      ["Contacts", "/contacts", Users, "contacts.view"],
      ["Debts", "/debts", HandCoins, "debts.view"],
      ["Shared", "/shared", Split, "shared.view"],
      ["Reports", "/reports", BarChart3, "reports.view"],
      ["Accounts", "/settings/accounts", Wallet, "accounts.view"],
      ["Categories", "/settings/categories", Tags, "categories.view"],
    ];
    for (const [label, to, icon, perm] of navDest) {
      if (!perm || can(perm)) out.push({ id: `nav:${to}`, label, icon, to, group: "Go to" });
    }
    if (can("contacts.view")) {
      for (const c of contacts.filter((x) => !x.connectionUid)) {
        out.push({
          id: `contact:${c.id}`,
          label: c.name,
          hint: "Contact",
          icon: Users,
          to: txnsByContact(c.id),
          group: "Contacts",
        });
      }
    }
    if (can("accounts.view")) {
      for (const a of accounts) {
        out.push({
          id: `account:${a.id}`,
          label: a.name,
          hint: "Account ledger",
          icon: Wallet,
          to: accountLedgerPath(a.id),
          group: "Accounts",
        });
      }
    }
    if (can("transactions.view")) {
      for (const c of categories) {
        out.push({
          id: `category:${c.id}`,
          label: c.name,
          hint: "Category transactions",
          icon: Tags,
          to: txnsByCategory(c.id),
          group: "Categories",
        });
      }
    }
    return out;
  }, [contacts, accounts, categories, can]);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    const matched = q
      ? items.filter((i) => i.label.toLowerCase().includes(q) || i.group.toLowerCase().includes(q))
      : items.filter((i) => i.group === "Go to");
    return matched.slice(0, 50);
  }, [items, query]);

  // Reset + focus on open; clamp active when results change.
  useEffect(() => {
    if (open) {
      setQuery("");
      setActive(0);
      // focus after the dialog mounts
      requestAnimationFrame(() => inputRef.current?.focus());
    }
  }, [open]);
  useEffect(() => setActive(0), [query]);

  function choose(item: Item | undefined) {
    if (!item) return;
    onOpenChange(false);
    navigate(item.to);
  }

  function onKeyDown(e: React.KeyboardEvent) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((a) => Math.min(a + 1, results.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((a) => Math.max(a - 1, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      choose(results[active]);
    }
  }

  // Group results in display order while keeping a flat index for keyboard nav.
  let flatIndex = -1;
  const groups = [...new Set(results.map((r) => r.group))];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent hideClose className="top-[12%] max-w-xl translate-y-0 gap-0 p-0">
        <div className="flex items-center gap-2 border-b px-3">
          <Search className="h-4 w-4 shrink-0 text-muted-foreground" />
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={onKeyDown}
            placeholder="Search pages, contacts, accounts, categories…"
            className="h-12 w-full bg-transparent text-sm outline-none placeholder:text-muted-foreground"
          />
        </div>
        <div className="max-h-[60vh] overflow-y-auto p-2">
          {results.length === 0 ? (
            <p className="px-3 py-8 text-center text-sm text-muted-foreground">No matches.</p>
          ) : (
            groups.map((group) => (
              <div key={group} className="mb-1">
                <p className="px-2 py-1 text-xs font-medium text-muted-foreground">{group}</p>
                {results
                  .filter((r) => r.group === group)
                  .map((r) => {
                    flatIndex++;
                    const idx = flatIndex;
                    const Icon = r.icon;
                    return (
                      <button
                        key={r.id}
                        type="button"
                        onClick={() => choose(r)}
                        onMouseMove={() => setActive(idx)}
                        className={cn(
                          "flex w-full items-center gap-2.5 rounded-md px-2 py-2 text-left text-sm",
                          idx === active ? "bg-accent text-accent-foreground" : "text-foreground",
                        )}
                      >
                        <Icon className="h-4 w-4 shrink-0 text-muted-foreground" />
                        <span className="min-w-0 flex-1 truncate">{r.label}</span>
                        {r.hint && (
                          <span className="shrink-0 text-xs text-muted-foreground">{r.hint}</span>
                        )}
                      </button>
                    );
                  })}
              </div>
            ))
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
