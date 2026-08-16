// Subscribes to every workspace-scoped collection for the active workspace and
// exposes the raw arrays + lookup maps + derived helpers. Centralizing the live
// data here keeps derived calcs (balances, outstanding, tax) trivial for screens
// and is fine at v1 data volumes.

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { collection, orderBy, query, where } from "firebase/firestore";
import { db } from "@/firebase/config";
import { subscribeWithRetry } from "@/lib/firestoreRetry";
import { useWorkspace } from "@/workspace/WorkspaceProvider";
import type {
  Account,
  Budget,
  Category,
  Contact,
  Debt,
  Due,
  Membership,
  Transaction,
} from "@/types/models";
import {
  accountBalances,
  contactPosition,
  debtOutstanding,
  dueSettledAmount,
  type ContactPosition,
} from "@/lib/derive";

interface WorkspaceData {
  loading: boolean;
  error: string | null;
  accounts: Account[];
  categories: Category[];
  contacts: Contact[];
  debts: Debt[];
  dues: Due[];
  budgets: Budget[];
  members: Membership[];
  transactions: Transaction[];
  // lookup maps
  accountsById: Record<string, Account>;
  categoriesById: Record<string, Category>;
  contactsById: Record<string, Contact>;
  debtsById: Record<string, Debt>;
  // derived
  balanceOf: (accountId: string) => number;
  outstandingOf: (debtId: string) => number;
  positionOf: (contactId: string) => ContactPosition;
  settledOf: (dueId: string) => number;
}

const DataContext = createContext<WorkspaceData | undefined>(undefined);

function useLiveCollection<T>(
  name: string,
  workspaceId: string | null,
  opts: {
    orderByField?: string;
    desc?: boolean;
    // Own-records scope: filter this collection to one contact (field, value),
    // and `enabled: false` skips the subscription entirely (empty result).
    scopeField?: string;
    scopeValue?: string | null;
    enabled?: boolean;
  } = {},
): { data: T[]; loading: boolean; error: string | null } {
  const [data, setData] = useState<T[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const enabled = opts.enabled !== false;

  useEffect(() => {
    if (!workspaceId || !enabled) {
      setData([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    const constraints = [where("workspaceId", "==", workspaceId)];
    if (opts.scopeField && opts.scopeValue) {
      constraints.push(where(opts.scopeField, "==", opts.scopeValue) as never);
    }
    if (opts.orderByField) {
      constraints.push(orderBy(opts.orderByField, opts.desc ? "desc" : "asc") as never);
    }
    const q = query(collection(db, name), ...constraints);
    const unsub = subscribeWithRetry(
      q,
      (snap) => {
        setData(snap.docs.map((d) => d.data() as T));
        setError(null);
        setLoading(false);
      },
      (e) => {
        setError(e.message);
        setLoading(false);
      },
    );
    return unsub;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [name, workspaceId, opts.orderByField, opts.desc, opts.scopeField, opts.scopeValue, enabled]);

  return { data, loading, error };
}

export function WorkspaceDataProvider({ children }: { children: ReactNode }) {
  const { activeWorkspaceId, role, memberships } = useWorkspace();
  const ws = activeWorkspaceId;

  // Own-records scope: a role flagged scope.own may only read records of the
  // member's linked contact — mirror the mobile app and the security rules.
  const myMembership = memberships.find((m) => m.workspaceId === ws) ?? null;
  const restricted = role?.permissions?.["scope.own"] === true;
  const ownContactId = myMembership?.linkedContactId ?? null;
  // Until the role is known, hold off subscribing (prevents a denied
  // unfiltered query flashing an error for restricted members).
  const scopeReady = role != null;
  const restrictedBlocked = restricted && !ownContactId;

  const accounts = useLiveCollection<Account>("accounts", ws, {
    enabled: scopeReady && !restricted,
  });
  const categories = useLiveCollection<Category>("categories", ws, { enabled: scopeReady });
  const contacts = useLiveCollection<Contact>("contacts", ws, {
    enabled: scopeReady && !restrictedBlocked,
    scopeField: restricted ? "id" : undefined,
    scopeValue: restricted ? ownContactId : undefined,
  });
  const debts = useLiveCollection<Debt>("debts", ws, {
    enabled: scopeReady && !restrictedBlocked,
    scopeField: restricted ? "contactId" : undefined,
    scopeValue: restricted ? ownContactId : undefined,
  });
  const budgets = useLiveCollection<Budget>("budgets", ws, {
    enabled: scopeReady && !restricted,
  });
  const members = useLiveCollection<Membership>("memberships", ws);
  const dues = useLiveCollection<Due>("dues", ws, {
    orderByField: "dueDate",
    enabled: scopeReady && !restrictedBlocked,
    scopeField: restricted ? "contactId" : undefined,
    scopeValue: restricted ? ownContactId : undefined,
  });
  const transactions = useLiveCollection<Transaction>("transactions", ws, {
    orderByField: "date",
    desc: true,
    enabled: scopeReady && !restrictedBlocked,
    scopeField: restricted ? "contactId" : undefined,
    scopeValue: restricted ? ownContactId : undefined,
  });

  const value = useMemo<WorkspaceData>(() => {
    const accountsById = Object.fromEntries(accounts.data.map((a) => [a.id, a]));
    const categoriesById = Object.fromEntries(categories.data.map((c) => [c.id, c]));
    const contactsById = Object.fromEntries(contacts.data.map((c) => [c.id, c]));
    const debtsById = Object.fromEntries(debts.data.map((d) => [d.id, d]));

    const balances = accountBalances(accounts.data, transactions.data, debtsById);

    return {
      loading:
        accounts.loading ||
        categories.loading ||
        contacts.loading ||
        debts.loading ||
        budgets.loading ||
        members.loading ||
        dues.loading ||
        transactions.loading,
      error:
        accounts.error ||
        categories.error ||
        contacts.error ||
        debts.error ||
        budgets.error ||
        members.error ||
        dues.error ||
        transactions.error,
      accounts: accounts.data,
      categories: categories.data,
      contacts: contacts.data,
      debts: debts.data,
      dues: dues.data,
      budgets: budgets.data,
      members: members.data,
      transactions: transactions.data,
      accountsById,
      categoriesById,
      contactsById,
      debtsById,
      balanceOf: (id) => balances[id] ?? 0,
      outstandingOf: (id) =>
        debtsById[id] ? debtOutstanding(debtsById[id], transactions.data) : 0,
      positionOf: (id) => contactPosition(id, debts.data, transactions.data),
      settledOf: (id) => {
        const due = dues.data.find((d) => d.id === id);
        return due ? dueSettledAmount(due, transactions.data) : 0;
      },
    };
  }, [
    accounts,
    categories,
    contacts,
    debts,
    budgets,
    members,
    dues,
    transactions,
  ]);

  return <DataContext.Provider value={value}>{children}</DataContext.Provider>;
}

export function useData(): WorkspaceData {
  const ctx = useContext(DataContext);
  if (!ctx) throw new Error("useData must be used within <WorkspaceDataProvider>");
  return ctx;
}
