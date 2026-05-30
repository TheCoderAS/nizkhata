// Generic placeholder for feature screens not yet built in this foundation
// phase (build order steps 5-11). Each is permission-gated at the route level,
// so this also doubles as a live demonstration that gating works.

import { EmptyState } from "@/components/states";

export function PagePlaceholder({
  title,
  buildStep,
}: {
  title: string;
  buildStep: string;
}) {
  return (
    <div>
      <h1 className="mb-4 text-xl font-semibold">{title}</h1>
      <EmptyState
        title={`${title} is not built yet`}
        hint={`Planned for build order: ${buildStep}. The foundation (data model, security rules, auth, workspace + permission context, app shell) is in place.`}
      />
    </div>
  );
}
