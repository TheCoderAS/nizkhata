import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
import '../widgets/entity_card_list.dart';
import 'category_form.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  // The Net column reflects the chosen range: week / month / year / financial
  // year / custom (a user-picked From/To window).
  PeriodKind _period = PeriodKind.fy;
  DateTime? _customFrom;
  DateTime? _customTo;

  static const _periodOptions = [
    PeriodKind.week,
    PeriodKind.month,
    PeriodKind.year,
    PeriodKind.fy,
    PeriodKind.custom,
  ];

  Future<void> _pickCustom(bool isFrom) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_customFrom ?? DateTime(now.year, now.month, 1))
        : (_customTo ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        final d = DateTime(picked.year, picked.month, picked.day);
        if (isFrom) {
          _customFrom = d;
        } else {
          _customTo = d;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final canManage = ws.can('categories.manage');
    final canViewTxns = ws.can('transactions.view');
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final fyStartMonth = ws.activeWorkspace?.fyStartMonth ?? 4;

    final now = DateTime.now();
    final ({DateTime start, DateTime end}) range;
    if (_period == PeriodKind.custom) {
      final start = _customFrom ?? DateTime(now.year, now.month, 1);
      final toDay = _customTo ?? DateTime(now.year, now.month, now.day);
      // End is exclusive; include the whole To-day by advancing one day.
      range = (start: start, end: toDay.add(const Duration(days: 1)));
    } else {
      range = resolvePeriod(_period, now, fyStartMonth);
    }

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
            ? FloatingActionButton(
              onPressed: () => showCategoryForm(context),
              tooltip: 'Add category',
              child: const Icon(Icons.add),
            )
            : null,
        body: Column(
          children: [
            if (_period == PeriodKind.custom)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event, size: 18),
                        label: Text(
                          _customFrom != null ? formatDate(_customFrom!) : 'From',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () => _pickCustom(true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event, size: 18),
                        label: Text(
                          _customTo != null ? formatDate(_customTo!) : 'To',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () => _pickCustom(false),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _CategoryList(
                    kind: 'expense',
                    categories: data.categories,
                    canManage: canManage,
                    canViewTxns: canViewTxns,
                    amountByCategory: amountByCategory,
                    currency: currency,
                  ),
                  _CategoryList(
                    kind: 'income',
                    categories: data.categories,
                    canManage: canManage,
                    canViewTxns: canViewTxns,
                    amountByCategory: amountByCategory,
                    currency: currency,
                  ),
                ],
              ),
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
  final bool canViewTxns;
  final Map<String, double> amountByCategory;
  final String currency;
  const _CategoryList({
    required this.kind,
    required this.categories,
    required this.canManage,
    required this.canViewTxns,
    required this.amountByCategory,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final items = categories.where((c) => c.kind == kind).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (items.isEmpty) {
      return EmptyView(icon: Icons.category_outlined, title: 'No $kind categories');
    }
    return EntityCardList<AppCategory>(
      listId: 'categories-$kind',
      rows: items,
      leading: (c) => _CategoryBadge(name: c.name, kind: c.kind),
      fields: [
        CardField<AppCategory>(
          key: 'name',
          label: 'Name',
          role: CardRole.title,
          locked: true,
          sortValue: (c) => c.name.toLowerCase(),
          text: (c) => c.name,
        ),
        CardField<AppCategory>(
          key: 'amount',
          label: 'Net',
          role: CardRole.amount,
          sortValue: (c) => amountByCategory[c.id] ?? 0,
          widget: (c) => Text(
            formatMoney(amountByCategory[c.id] ?? 0, currency),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        CardField<AppCategory>(
          key: 'source',
          label: 'Source',
          icon: Icons.tune,
          sortValue: (c) => c.isSystem ? 'System' : 'Custom',
          widget: (c) {
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
      trailing: (canManage || canViewTxns)
          ? (c) => PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'transactions') context.push('/txns?category=${c.id}');
                  if (v == 'edit') showCategoryForm(context, existing: c);
                  if (v == 'delete') _confirmDelete(context, c);
                },
                itemBuilder: (_) => [
                  if (canViewTxns)
                    const PopupMenuItem(value: 'transactions', child: Text('View transactions')),
                  if (canManage)
                    PopupMenuItem(value: 'edit', enabled: !c.isSystem, child: const Text('Edit')),
                  if (canManage)
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

/// Colored, deterministic badge for a category card — a soft gradient tile with
/// an income/expense glyph, so the list reads with colour instead of grey rows.
class _CategoryBadge extends StatelessWidget {
  final String name;
  final String kind;
  const _CategoryBadge({required this.name, required this.kind});

  @override
  Widget build(BuildContext context) {
    final g = avatarGradient(name.isEmpty ? '?' : name);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [g.from.withValues(alpha: 0.85), g.to.withValues(alpha: 0.85)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        kind == 'income' ? Icons.south_west : Icons.north_east,
        size: 20,
        color: Colors.white,
      ),
    );
  }
}
