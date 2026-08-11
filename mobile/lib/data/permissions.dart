// Permission catalog + system role templates + seed data.
// Ports src/types/permissions.ts and src/workspace/seed.ts 1:1.

const kPermissions = <String>[
  'transactions.view',
  'transactions.create',
  'transactions.edit',
  'transactions.delete',
  'accounts.view',
  'accounts.manage',
  'categories.view',
  'categories.manage',
  'contacts.view',
  'contacts.manage',
  'debts.view',
  'debts.manage',
  'dues.view',
  'dues.manage',
  'shared.view',
  'shared.manage',
  'reports.view',
  'reports.export',
  'members.view',
  'members.invite',
  'members.remove',
  'roles.view',
  'roles.manage',
  'workspace.edit',
  'workspace.delete',
];

const kDangerousPermissions = <String>[
  'roles.manage',
  'members.remove',
  'workspace.delete',
];

Map<String, bool> _allTrue() => {for (final p in kPermissions) p: true};

Map<String, bool> _withFalse(List<String> keys) {
  final m = _allTrue();
  for (final k in keys) {
    m[k] = false;
  }
  return m;
}

Map<String, bool> _only(List<String> keys) => {for (final k in keys) k: true};

final _viewPerms = kPermissions.where((p) => p.endsWith('.view')).toList();

/// System role names in seed order.
const kSystemRoleOrder = <String>['Owner', 'Admin', 'Editor', 'Viewer'];

Map<String, Map<String, bool>> systemRoleTemplates() => {
      'Owner': _allTrue(),
      'Admin': _withFalse(['workspace.delete']),
      'Editor': _only([
        ..._viewPerms,
        'transactions.create',
        'transactions.edit',
        'transactions.delete',
        'accounts.manage',
        'categories.manage',
        'contacts.manage',
        'debts.manage',
        'dues.manage',
        'shared.manage',
        'reports.export',
      ]),
      'Viewer': _only(_viewPerms),
    };

class SeedCategory {
  final String name;
  final String kind;
  const SeedCategory(this.name, this.kind);
}

const kDefaultCategories = <SeedCategory>[
  SeedCategory('Salary', 'income'),
  SeedCategory('Bonus', 'income'),
  SeedCategory('Interest (CASA/FD)', 'income'),
  SeedCategory('Gift', 'income'),
  SeedCategory('Reimbursement', 'income'),
  SeedCategory('Refund', 'income'),
  SeedCategory('Other Income', 'income'),
  SeedCategory('Food', 'expense'),
  SeedCategory('Transport', 'expense'),
  SeedCategory('Rent', 'expense'),
  SeedCategory('Utilities', 'expense'),
  SeedCategory('Shopping', 'expense'),
  SeedCategory('Health', 'expense'),
  SeedCategory('Entertainment', 'expense'),
  SeedCategory('Loan Interest', 'expense'),
  SeedCategory('Bank Charges', 'expense'),
  SeedCategory('Taxes & GST', 'expense'),
  SeedCategory('Other Expense', 'expense'),
];
