// The bell in the app bar: what needs attention, with a count. It used to be
// a card at the top of the dashboard; a list of reminders there pushed the
// numbers people open the app for below the fold, so it lives here instead.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../core/ws_time.dart';
import '../data/derive.dart';
import '../data/mutations.dart';
import '../services/recurrence.dart';
import '../services/title_tokens.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';

class _Attention {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _Attention({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class AttentionBell extends StatefulWidget {
  const AttentionBell({super.key});
  @override
  State<AttentionBell> createState() => _AttentionBellState();
}

class _AttentionBellState extends State<AttentionBell> {
  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final data = context.watch<DataController>();
    final items = _items(context, data, ws, ws.currency, WsTime.now());
    final n = items.length;
    return IconButton(
      key: const Key('attention-bell'),
      tooltip: n == 0 ? 'Nothing needs attention' : '$n thing${n == 1 ? '' : 's'} need${n == 1 ? 's' : ''} attention',
      onPressed: () => _open(context, items),
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text(n > 99 ? '99+' : '$n'),
        child: Icon(n > 0 ? Icons.notifications : Icons.notifications_none),
      ),
    );
  }

  void _open(BuildContext context, List<_Attention> items) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.75),
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 36, color: AppColors.accent2),
                      SizedBox(height: 10),
                      Text('All clear', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('Nothing needs your attention right now.'),
                    ],
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Needs attention', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    for (final a in items) _tile(sheet, a),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext sheet, _Attention a) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: a.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(a.icon, size: 18, color: a.color),
      ),
      title: Text(a.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      subtitle: Text(a.subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () {
        Navigator.of(sheet).pop();
        a.onTap();
      },
    );
  }

  /// What needs attention: overdue receivables, dues this week,
  /// uncategorised transactions, stale statement imports, and recurring
  /// transactions whose next occurrence has arrived.
  List<_Attention> _items(
      BuildContext context, DataController data, WorkspaceController ws, String currency, DateTime now) {
    final items = <_Attention>[];
    final today = DateTime(now.year, now.month, now.day);

    // Overdue receivables + dues in the next 7 days.
    var overdueCount = 0;
    var overdueAmount = 0.0;
    var weekCount = 0;
    for (final d in data.dues) {
      final st = dueStatusFromSettled(d, data.settledOf(d.id));
      if (st != 'open' && st != 'partial') continue;
      final remaining = d.amount - data.settledOf(d.id);
      if (remaining <= 0.005) continue;
      if (d.direction == 'receivable' && d.dueDate.isBefore(today)) {
        overdueCount++;
        overdueAmount += remaining;
      } else if (!d.dueDate.isBefore(today) && d.dueDate.isBefore(today.add(const Duration(days: 8)))) {
        weekCount++;
      }
    }
    if (overdueCount > 0) {
      items.add(_Attention(
        icon: Icons.notifications_active_outlined,
        color: AppColors.danger,
        title: '$overdueCount overdue receivable${overdueCount == 1 ? '' : 's'}',
        subtitle: '${formatMoney(overdueAmount, currency)} waiting to be collected',
        onTap: () => context.go('/dues'),
      ));
    }
    if (weekCount > 0) {
      items.add(_Attention(
        icon: Icons.event_outlined,
        color: AppColors.brand,
        title: '$weekCount due${weekCount == 1 ? '' : 's'} in the next 7 days',
        subtitle: 'See the calendar for the full picture',
        onTap: () => context.push('/calendar'),
      ));
    }

    // Uncategorised transactions (imports mostly).
    final uncategorized = data.transactions
        .where((t) => t.lines.any((l) => (l.type == 'expense' || l.type == 'income') && l.categoryId == null))
        .length;
    if (uncategorized > 0 && ws.can('transactions.edit')) {
      items.add(_Attention(
        icon: Icons.category_outlined,
        color: AppColors.accent2,
        title: '$uncategorized uncategorised transaction${uncategorized == 1 ? '' : 's'}',
        subtitle: 'Categorise in bulk, grouped by merchant',
        onTap: () => context.push('/categorize'),
      ));
    }

    // Stale statement imports: accounts that HAVE imported history whose
    // newest imported transaction is over 30 days old.
    if (ws.can('transactions.create')) {
      for (final a in data.accounts) {
        DateTime? lastImport;
        for (final t in data.transactions) {
          if (t.accountId != a.id || t.importKey == null) continue;
          if (lastImport == null || t.date.isAfter(lastImport)) lastImport = t.date;
        }
        if (lastImport == null) continue;
        final days = today.difference(DateTime(lastImport.year, lastImport.month, lastImport.day)).inDays;
        if (days > 30) {
          items.add(_Attention(
            icon: Icons.upload_file_outlined,
            color: AppColors.brandTo,
            title: '${a.name}: statement due for import',
            subtitle: 'Last imported $days days ago',
            onTap: () => context.push('/import?account=${a.id}'),
          ));
        }
      }
    }

    // Recurring transactions whose next occurrence has arrived (suggest only).
    if (ws.can('transactions.create')) {
      for (final s in recurringTxnSuggestions(data.transactions, now)) {
        items.add(_Attention(
          icon: Icons.repeat,
          color: AppColors.accent2,
          title: 'Add "${_recurringNote(s, ws.fyStartMonth) ?? 'Transaction'}"'
              ' for ${formatDate(s.nextDate)}',
          subtitle: 'Recurring ${s.template.recurrence} · ${formatMoney(s.template.totalAmount, currency)}',
          onTap: () => _addRecurringTxn(context, s),
        ));
      }
    }

    return items;
  }

  /// The note this occurrence will carry: re-rendered from the pattern for the
  /// new date, so a suggestion never offers to add last month's label again.
  static String? _recurringNote(TxnSuggestion s, int fyStartMonth) {
    final pattern = s.template.notePattern;
    if (pattern == null) return s.template.note;
    return renderTokens(pattern, s.nextDate, fyStartMonth: fyStartMonth);
  }

  Future<void> _addRecurringTxn(BuildContext context, TxnSuggestion s) async {
    final wsC = context.read<WorkspaceController>();
    final wsId = wsC.activeWorkspaceId;
    final fyStart = wsC.fyStartMonth;
    final note = _recurringNote(s, fyStart);
    final user = context.read<AuthController>().user;
    final currency = wsC.currency;
    if (wsId == null || user == null) return;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Add recurring transaction?'),
        content: Text('"${note ?? 'Transaction'}" for '
            '${formatDate(s.nextDate)}, ${formatMoney(s.template.totalAmount, currency)}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final micros = WsTime.now().microsecondsSinceEpoch;
    var i = 0;
    final lines = [
      for (final l in s.template.lines) (l.toMap()..['lineId'] = 'rec_${micros}_l${i++}'),
    ];
    try {
      await Mutations(Actor.fromUser(user)).createTransaction(
        wsId,
        date: s.nextDate,
        note: note,
        notePattern: s.template.notePattern,
        accountId: s.template.accountId,
        contactId: s.template.contactId,
        totalAmount: s.template.totalAmount,
        financialYear: financialYearOf(s.nextDate, fyStart),
        lines: lines,
        recurrence: s.template.recurrence,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction added')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}
