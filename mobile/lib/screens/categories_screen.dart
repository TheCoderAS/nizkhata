import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import 'category_form.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final canManage = ws.can('categories.manage');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
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
            _CategoryList(kind: 'expense', categories: data.categories, canManage: canManage),
            _CategoryList(kind: 'income', categories: data.categories, canManage: canManage),
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
  const _CategoryList({required this.kind, required this.categories, required this.canManage});

  @override
  Widget build(BuildContext context) {
    final items = categories.where((c) => c.kind == kind).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (items.isEmpty) {
      return EmptyView(title: 'No $kind categories');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = items[i];
        final cs = Theme.of(context).colorScheme;
        return ListTile(
          title: Text(c.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.isSystem ? 'System' : 'Custom',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.isSystem ? cs.onSurfaceVariant : AppColors.accent2,
                ),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') showCategoryForm(context, existing: c);
                    if (v == 'delete') _confirmDelete(context, c);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', enabled: !c.isSystem, child: const Text('Edit')),
                    PopupMenuItem(value: 'delete', enabled: !c.isSystem, child: const Text('Delete')),
                  ],
                ),
            ],
          ),
        );
      },
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
