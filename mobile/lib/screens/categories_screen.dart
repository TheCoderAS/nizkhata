import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import '../widgets/data_table_view.dart';
import 'category_form.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  // The Net column reflects the chosen range: week / month / year / financial year.
  PeriodKind _period = PeriodKind.fy;

  static const _periodOptions = [
    PeriodKind.week,
    PeriodKind.month,
    PeriodKind.year,
    PeriodKind.fy,
  ];

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final canManage = ws.can('categories.manage');
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final fyStartMonth = ws.activeWorkspace?.fyStartMonth ?? 4;

    final range = resolvePeriod(_period, DateTime.now(), fyStartMonth);

    // Net amount per category within the selected range — the sum of line
    // amounts tagged with it (total spent for expense categories, earned for
    // income). Derived; cheap at v1 volumes.
    final amountByCategory = <String, double>{};
    for (final t in data.transactions) {
      if (t.date.isBefore(range.start) || !t.date.isBefore(range.end)) continue;
      for (final l in t.lines) {
        if (l.categoryId == null) continue;
        amountByCategory[l.categoryId!] =
            roundMoney((amountByCategory[l.categoryId!] ?? 0) + l.amount);
      }
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          actions: [
            PopupMenuButton<PeriodKind>(
              initialValue: _period,
              tooltip: 'Period',
              onSelected: (v) => setState(() => _period = v),
              itemBuilder: (_) => _periodOptions
                  .map((k) => PopupMenuItem(value: k, child: Text(periodLabels[k]!)))
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(periodLabels[_period]!),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Expense'),
              Tab(text: 'Income'),
            ],
          ),
        ),
        floatingActionButton: canManage
            ? FloatingActionButton.extended(
                onPressed: () => showCategoryForm(context),
                icon: const Icon(Icons.add),
                label: const Text('Category'),
              )
            : null,
        body: TabBarView(
          children: [
            _CategoryList(
              kind: 'expense',
              categories: data.categories,
              canManage: canManage,
              amountByCategory: amountByCategory,
              currency: currency,
            ),
            _CategoryList(
              kind: 'income',
              categories: data.categories,
              canManage: canManage,
              amountByCategory: amountByCategory,
              currency: currency,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  final String kind;
  final List<AppCategory> categories;
  final bool canManage;
  final Map<String, double> amountByCategory;
  final String currency;
  const _CategoryList({
    required this.kind,
    required this.categories,
    required this.canManage,
    required this.amountByCategory,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final items = categories.where((c) => c.kind == kind).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (items.isEmpty) {
      return EmptyView(title: 'No $kind categories');
    }
    return DataTableView<AppCategory>(
      tableId: 'categories-$kind',
      rows: items,
      columns: [
        DataColumn2<AppCategory>(
          key: 'name',
          label: 'Name',
          locked: true,
          defaultWidth: 180,
          sortValue: (c) => c.name.toLowerCase(),
          cell: (c) => Text(c.name, overflow: TextOverflow.ellipsis),
        ),
        DataColumn2<AppCategory>(
          key: 'amount',
          label: 'Net',
          numeric: true,
          defaultWidth: 130,
          sortValue: (c) => amountByCategory[c.id] ?? 0,
          cell: (c) => Text(
            formatMoney(amountByCategory[c.id] ?? 0, currency),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        DataColumn2<AppCategory>(
          key: 'source',
          label: 'Source',
          defaultWidth: 120,
          sortValue: (c) => c.isSystem ? 'System' : 'Custom',
          cell: (c) {
            final cs = Theme.of(context).colorScheme;
            if (c.isSystem) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'System',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            }
            return const Text(
              'Custom',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accent2,
              ),
            );
          },
        ),
      ],
      trailing: canManage
          ? (c) => PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') showCategoryForm(context, existing: c);
                  if (v == 'delete') _confirmDelete(context, c);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', enabled: !c.isSystem, child: const Text('Edit')),
                  PopupMenuItem(value: 'delete', enabled: !c.isSystem, child: const Text('Delete')),
                ],
              )
          : null,
    );
  }

  void _confirmDelete(BuildContext context, AppCategory c) {
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    final user = context.read<AuthController>().user;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${c.name}"?'),
        content: const Text('This removes the category.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              if (ws == null || user == null) return;
              try {
                await Mutations(Actor.fromUser(user)).deleteCategory(ws, c.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category deleted')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
