// Dashboard (§6.2). Full derived metrics (income/expense/net, custodial held,
// spend-by-category, upcoming dues) land in build step 9. For the foundation it
// shows the active workspace + the current user's effective permissions, which
// is the most useful thing to verify the permission plumbing end to end.

import { useWorkspace } from "@/workspace/WorkspaceProvider";
import { PERMISSIONS } from "@/types/permissions";
import { financialYearOf } from "@/lib/financialYear";

export function Dashboard() {
  const { activeWorkspace, role } = useWorkspace();

  const fy = activeWorkspace
    ? financialYearOf(new Date(), activeWorkspace.fyStartMonth)
    : "—";

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Dashboard</h1>
        <p className="text-sm text-gray-500">
          {activeWorkspace?.name ?? "No workspace"} · FY {fy} ·{" "}
          {activeWorkspace?.baseCurrency}
        </p>
      </div>

      <div className="rounded-md border border-gray-200 p-4">
        <h2 className="mb-2 text-sm font-semibold text-gray-700">
          Your role: {role?.name ?? "—"}
        </h2>
        <div className="grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-3">
          {PERMISSIONS.map((p) => {
            const on = role?.permissions?.[p] === true;
            return (
              <div key={p} className="flex items-center gap-2">
                <span className={on ? "text-green-600" : "text-gray-300"}>
                  {on ? "✓" : "✕"}
                </span>
                <span className={on ? "text-gray-700" : "text-gray-400"}>
                  {p}
                </span>
              </div>
            );
          })}
        </div>
      </div>

      <p className="text-sm text-gray-400">
        Metrics (income / expense / net, custodial held, spend-by-category,
        upcoming dues, recent transactions) arrive with the reporting layer.
      </p>
    </div>
  );
}
