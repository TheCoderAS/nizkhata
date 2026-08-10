import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import 'budget_form.dart';

class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final fyStart = ws.activeWorkspace?.fyStartMonth ?? 4;
    final canManage = ws.can('categories.manage');

    final rows = budgetProgress(data.budgets, data.transactions, data.categoriesById, fyStart);

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => showBudgetForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Budget'),
            )
          : null,
      body: rows.isEmpty
          ? EmptyView(
              title: 'No budgets yet',
              hint: 'Set a monthly or yearly limit on an expense category to track spending against it.',
              action: canManage
                  ? FilledButton(onPressed: () => showBudgetForm(context), child: const Text('New budget'))
                  : null,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [
                for (final period in const ['monthly', 'yearly'])
                  ..._group(context, period, rows.where((r) => r.budget.period == period).toList(), currency, canManage),
              ],
            ),
    );
  }

  List<Widget> _group(
      BuildContext context, String period, List<BudgetProgress> rows, String currency, bool canManage) {
    if (rows.isEmpty) return const [];
    final label = period == 'yearly' ? 'Yearly budgets' : 'Monthly budgets';
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ),
      for (final p in rows) _BudgetCard(progress: p, currency: currency, canManage: canManage),
    ];
  }
}

class _BudgetCard extends StatelessWidget {
  final BudgetProgress progress;
  final String currency;
  final bool canManage;
  const _BudgetCard({required this.progress, required this.currency, required this.canManage});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = progress;
    final over = p.spent > p.limit;
    final remaining = p.limit - p.spent;
    final periodLabel = p.budget.period == 'yearly' ? 'Yearly' : 'Monthly';
    final barColor = p.ratio > 1
        ? AppColors.danger
        : p.ratio > 0.8
            ? Colors.orange
            : cs.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(p.categoryName,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          Text(periodLabel,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatMoney(p.spent, currency)} / ${formatMoney(p.limit, currency)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: over ? AppColors.danger : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') showBudgetForm(context, existing: p.budget);
                      if (v == 'delete') _confirmDelete(context, p);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: p.ratio.clamp(0.0, 1.0).toDouble(),
                minHeight: 8,
                backgroundColor: cs.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              over
                  ? 'Over by ${formatMoney(-remaining, currency)}'
                  : '${formatMoney(remaining, currency)} left',
              style: TextStyle(fontSize: 12, color: over ? AppColors.danger : cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, BudgetProgress p) {
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    final user = context.read<AuthController>().user;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete budget?'),
        content: Text('This removes the budget for "${p.categoryName}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              if (ws == null || user == null) return;
              try {
                await Mutations(Actor.fromUser(user)).deleteBudget(ws, p.budget.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Budget deleted')));
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
