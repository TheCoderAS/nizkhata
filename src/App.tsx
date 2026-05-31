// Routing + provider composition. Every feature route is wrapped in both an
// auth gate and a permission gate (§6). Rules are the real guard.

import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { lazy, type ReactNode } from "react";
import { AuthProvider } from "@/auth/AuthProvider";
import { WorkspaceProvider } from "@/workspace/WorkspaceProvider";
import { WorkspaceDataProvider } from "@/data/WorkspaceDataProvider";
import { SharedDataProvider } from "@/data/SharedDataProvider";
import { ToastProvider } from "@/components/ui/toast";
import { PWAPrompt } from "@/components/PWAPrompt";
import { RequireAuth, RequirePermission } from "@/components/ProtectedRoute";
import { AppShell } from "@/components/AppShell";
import { Login } from "@/pages/Login";
import { Dashboard } from "@/pages/Dashboard";
import type { Permission } from "@/types/permissions";

// Code-split the secondary feature screens so the initial bundle stays small —
// only Login + Dashboard (the entry + index) load eagerly. Pages use named
// exports, so map each to a default for React.lazy. Routed content is wrapped
// in a single <Suspense> below.
const lazyPage = <K extends string>(loader: () => Promise<Record<K, React.ComponentType>>, key: K) =>
  lazy(() => loader().then((m) => ({ default: m[key] })));

const Accounts = lazyPage(() => import("@/pages/Accounts"), "Accounts");
const AccountLedger = lazyPage(() => import("@/pages/AccountLedger"), "AccountLedger");
const Categories = lazyPage(() => import("@/pages/Categories"), "Categories");
const Budgets = lazyPage(() => import("@/pages/Budgets"), "Budgets");
const Contacts = lazyPage(() => import("@/pages/Contacts"), "Contacts");
const ContactDetail = lazyPage(() => import("@/pages/ContactDetail"), "ContactDetail");
const Debts = lazyPage(() => import("@/pages/Debts"), "Debts");
const Transactions = lazyPage(() => import("@/pages/Transactions"), "Transactions");
const Dues = lazyPage(() => import("@/pages/Dues"), "Dues");
const Reports = lazyPage(() => import("@/pages/Reports"), "Reports");
const Activity = lazyPage(() => import("@/pages/Activity"), "Activity");
const Shared = lazyPage(() => import("@/pages/Shared"), "Shared");
const Members = lazyPage(() => import("@/pages/Members"), "Members");
const Roles = lazyPage(() => import("@/pages/Roles"), "Roles");
const WorkspaceSettings = lazyPage(() => import("@/pages/WorkspaceSettings"), "WorkspaceSettings");
const Account = lazyPage(() => import("@/pages/Account"), "Account");

function Gated({ perm, children }: { perm: Permission; children: ReactNode }) {
  return <RequirePermission perm={perm}>{children}</RequirePermission>;
}

export default function App() {
  return (
    <AuthProvider>
      <ToastProvider>
        <PWAPrompt />
        <BrowserRouter>
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route
              element={
                <RequireAuth>
                  <WorkspaceProvider>
                    <WorkspaceDataProvider>
                      <SharedDataProvider>
                        <AppShell />
                      </SharedDataProvider>
                    </WorkspaceDataProvider>
                  </WorkspaceProvider>
                </RequireAuth>
              }
            >
              <Route index element={<Dashboard />} />
              <Route
                path="transactions"
                element={
                  <Gated perm="transactions.view">
                    <Transactions />
                  </Gated>
                }
              />
              <Route
                path="dues"
                element={
                  <Gated perm="dues.view">
                    <Dues />
                  </Gated>
                }
              />
              <Route
                path="contacts"
                element={
                  <Gated perm="contacts.view">
                    <Contacts />
                  </Gated>
                }
              />
              <Route
                path="contacts/:contactId"
                element={
                  <Gated perm="contacts.view">
                    <ContactDetail />
                  </Gated>
                }
              />
              <Route
                path="debts"
                element={
                  <Gated perm="debts.view">
                    <Debts />
                  </Gated>
                }
              />
              <Route
                path="reports"
                element={
                  <Gated perm="reports.view">
                    <Reports />
                  </Gated>
                }
              />
              <Route
                path="activity"
                element={
                  <Gated perm="reports.view">
                    <Activity />
                  </Gated>
                }
              />
              <Route
                path="shared"
                element={
                  <Gated perm="shared.view">
                    <Shared />
                  </Gated>
                }
              />
              {/* Settings group: data setup + admin + personal account */}
              <Route
                path="settings/accounts"
                element={
                  <Gated perm="accounts.view">
                    <Accounts />
                  </Gated>
                }
              />
              <Route
                path="settings/accounts/:accountId/ledger"
                element={
                  <Gated perm="accounts.view">
                    <AccountLedger />
                  </Gated>
                }
              />
              <Route
                path="settings/categories"
                element={
                  <Gated perm="categories.view">
                    <Categories />
                  </Gated>
                }
              />
              <Route
                path="settings/budgets"
                element={
                  <Gated perm="categories.view">
                    <Budgets />
                  </Gated>
                }
              />
              <Route
                path="settings/members"
                element={
                  <Gated perm="members.view">
                    <Members />
                  </Gated>
                }
              />
              <Route
                path="settings/roles"
                element={
                  <Gated perm="roles.view">
                    <Roles />
                  </Gated>
                }
              />
              <Route
                path="settings/workspace"
                element={
                  <Gated perm="workspace.edit">
                    <WorkspaceSettings />
                  </Gated>
                }
              />
              <Route path="settings/account" element={<Account />} />
              {/* legacy redirects: old top-level paths now live under settings */}
              <Route path="accounts" element={<Navigate to="/settings/accounts" replace />} />
              <Route path="categories" element={<Navigate to="/settings/categories" replace />} />
            </Route>
          </Routes>
        </BrowserRouter>
      </ToastProvider>
    </AuthProvider>
  );
}
