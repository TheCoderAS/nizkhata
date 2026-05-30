// Permission catalog (§3). Every key is a boolean on a role's `permissions` map.

export const PERMISSIONS = [
  "transactions.view",
  "transactions.create",
  "transactions.edit",
  "transactions.delete",
  "accounts.view",
  "accounts.manage",
  "categories.view",
  "categories.manage",
  "contacts.view",
  "contacts.manage",
  "debts.view",
  "debts.manage",
  "dues.view",
  "dues.manage",
  "reports.view",
  "reports.export",
  "members.view",
  "members.invite",
  "members.remove",
  "roles.view",
  "roles.manage",
  "workspace.edit",
  "workspace.delete",
] as const;

export type Permission = (typeof PERMISSIONS)[number];

export type PermissionMap = Partial<Record<Permission, boolean>>;

// Permissions the UI must warn about before granting/using (§3).
export const DANGEROUS_PERMISSIONS: Permission[] = [
  "roles.manage",
  "members.remove",
  "workspace.delete",
];

// ---- system role templates (§3) -------------------------------------------

const ALL_TRUE: PermissionMap = Object.fromEntries(
  PERMISSIONS.map((p) => [p, true]),
) as PermissionMap;

function withFalse(...keys: Permission[]): PermissionMap {
  const map: PermissionMap = { ...ALL_TRUE };
  for (const k of keys) map[k] = false;
  return map;
}

function only(...keys: Permission[]): PermissionMap {
  const map: PermissionMap = {};
  for (const k of keys) map[k] = true;
  return map;
}

const VIEW_PERMS: Permission[] = PERMISSIONS.filter((p) =>
  p.endsWith(".view"),
);

export type SystemRoleName = "Owner" | "Admin" | "Editor" | "Viewer";

export const SYSTEM_ROLE_TEMPLATES: Record<SystemRoleName, PermissionMap> = {
  // Owner — everything.
  Owner: { ...ALL_TRUE },

  // Admin — everything except deleting the workspace.
  Admin: withFalse("workspace.delete"),

  // Editor — all *.view + manage/create/edit/delete on the data collections +
  // reports.export. No members / roles / workspace control.
  Editor: only(
    ...VIEW_PERMS,
    "transactions.create",
    "transactions.edit",
    "transactions.delete",
    "accounts.manage",
    "categories.manage",
    "contacts.manage",
    "debts.manage",
    "dues.manage",
    "reports.export",
  ),

  // Viewer — all *.view + reports.view only.
  Viewer: only(...VIEW_PERMS),
};

export const SYSTEM_ROLE_ORDER: SystemRoleName[] = [
  "Owner",
  "Admin",
  "Editor",
  "Viewer",
];
