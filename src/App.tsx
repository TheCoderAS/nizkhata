// Routing + provider composition. Every feature route is wrapped in both an
// auth gate and a permission gate (§6). Rules are the real guard.

import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import type { ReactNode } from "react";
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
import { Accounts } from "@/pages/Accounts";
import { Categories } from "@/pages/Categories";
import { Budgets } from "@/pages/Budgets";
import { Contacts } from "@/pages/Contacts";
import { ContactDetail } from "@/pages/ContactDetail";
import { Debts } from "@/pages/Debts";
import { Transactions } from "@/pages/Transactions";
import { Dues } from "@/pages/Dues";
import { Reports } from "@/pages/Reports";
import { Activity } from "@/pages/Activity";
import { Shared } from "@/pages/Shared";
import { Members } from "@/pages/Members";
import { Roles } from "@/pages/Roles";
import { WorkspaceSettings } from "@/pages/WorkspaceSettings";
import { Account } from "@/pages/Account";
import type { Permission } from "@/types/permissions";

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
                  <Gated perm="transactions.view">
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
