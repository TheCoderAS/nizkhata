// Routing + provider composition. Every feature route is wrapped in both an
// auth gate and a permission gate (§6). Feature screens are placeholders for the
// foundation phase; the gating is real.

import { BrowserRouter, Routes, Route } from "react-router-dom";
import { AuthProvider } from "@/auth/AuthProvider";
import { WorkspaceProvider } from "@/workspace/WorkspaceProvider";
import { RequireAuth, RequirePermission } from "@/components/ProtectedRoute";
import { AppShell } from "@/components/AppShell";
import { Login } from "@/pages/Login";
import { Dashboard } from "@/pages/Dashboard";
import { PagePlaceholder } from "@/pages/Placeholder";
import type { Permission } from "@/types/permissions";
import type { ReactNode } from "react";

function Gated({ perm, children }: { perm: Permission; children: ReactNode }) {
  return <RequirePermission perm={perm}>{children}</RequirePermission>;
}

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route
            element={
              <RequireAuth>
                <WorkspaceProvider>
                  <AppShell />
                </WorkspaceProvider>
              </RequireAuth>
            }
          >
            <Route index element={<Dashboard />} />
            <Route
              path="transactions"
              element={
                <Gated perm="transactions.view">
                  <PagePlaceholder title="Transactions" buildStep="6 — multi-line engine" />
                </Gated>
              }
            />
            <Route
              path="dues"
              element={
                <Gated perm="dues.view">
                  <PagePlaceholder title="Dues" buildStep="8" />
                </Gated>
              }
            />
            <Route
              path="contacts"
              element={
                <Gated perm="contacts.view">
                  <PagePlaceholder title="Contacts" buildStep="5" />
                </Gated>
              }
            />
            <Route
              path="accounts"
              element={
                <Gated perm="accounts.view">
                  <PagePlaceholder title="Accounts" buildStep="5" />
                </Gated>
              }
            />
            <Route
              path="categories"
              element={
                <Gated perm="categories.view">
                  <PagePlaceholder title="Categories" buildStep="5" />
                </Gated>
              }
            />
            <Route
              path="debts"
              element={
                <Gated perm="debts.view">
                  <PagePlaceholder title="Debts" buildStep="7" />
                </Gated>
              }
            />
            <Route
              path="reports"
              element={
                <Gated perm="reports.view">
                  <PagePlaceholder title="Reports" buildStep="9 + 11 (CSV)" />
                </Gated>
              }
            />
            <Route
              path="settings/members"
              element={
                <Gated perm="members.view">
                  <PagePlaceholder title="Members" buildStep="10" />
                </Gated>
              }
            />
            <Route
              path="settings/roles"
              element={
                <Gated perm="roles.view">
                  <PagePlaceholder title="Roles" buildStep="10" />
                </Gated>
              }
            />
            <Route
              path="settings/workspace"
              element={
                <Gated perm="workspace.edit">
                  <PagePlaceholder title="Workspace" buildStep="10" />
                </Gated>
              }
            />
          </Route>
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
