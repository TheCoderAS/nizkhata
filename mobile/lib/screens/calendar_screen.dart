import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';

/// Cash-flow calendar — a month grid with dues marked on their day (green
/// receivable / red payable dots, settled ones muted). Tapping a day opens the
/// existing dues-day drill-down.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();

    // Per-day open amounts for the visible month.
    final receivableByDay = <int, double>{};
    final payableByDay = <int, double>{};
    final settledDays = <int>{};
    for (final d in data.dues) {
      if (d.dueDate.year != _month.year || d.dueDate.month != _month.month) continue;
      final st = dueStatusFromSettled(d, data.settledOf(d.id));
      if (st == 'cancelled') continue;
      final remaining = d.amount - data.settledOf(d.id);
      if (st == 'settled' || remaining <= 0.005) {
        settledDays.add(d.dueDate.day);
        continue;
      }
      if (d.direction == 'receivable') {
        receivableByDay[d.dueDate.day] = (receivableByDay[d.dueDate.day] ?? 0) + remaining;
      } else {
        payableByDay[d.dueDate.day] = (payableByDay[d.dueDate.day] ?? 0) + remaining;
      }
    }
    var monthIn = 0.0, monthOut = 0.0;
    receivableByDay.forEach((_, v) => monthIn += v);
    payableByDay.forEach((_, v) => monthOut += v);

    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7; // Sun = 0
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = firstWeekday + daysInMonth;
    final rows = (cells / 7).ceil();

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () =>
                      setState(() => _month = DateTime(_month.year, _month.month - 1)),
                ),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () =>
                      setState(() => _month = DateTime(_month.year, _month.month + 1)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                  Expanded(
                    child: Center(
                      child: Text(d,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  for (var r = 0; r < rows; r++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var c = 0; c < 7; c++)
                            Expanded(child: _dayCell(context, r * 7 + c - firstWeekday + 1,
                                daysInMonth, receivableByDay, payableByDay, settledDays, today)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legend(AppColors.accent2, 'To receive ${formatMoney(monthIn, currency)}'),
                  const SizedBox(width: 18),
                  _legend(AppColors.danger, 'To pay ${formatMoney(monthOut, currency)}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _dayCell(
    BuildContext context,
    int day,
    int daysInMonth,
    Map<int, double> receivable,
    Map<int, double> payable,
    Set<int> settled,
    DateTime today,
  ) {
    if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final isToday =
        today.year == _month.year && today.month == _month.month && today.day == day;
    final hasR = receivable.containsKey(day);
    final hasP = payable.containsKey(day);
    final hasSettled = settled.contains(day);
    final date = DateTime(_month.year, _month.month, day);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: (hasR || hasP || hasSettled)
          ? () => context.push('/dues-day?date=${date.year}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}')
          : null,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isToday ? cs.primary.withValues(alpha: 0.12) : null,
          border: isToday ? Border.all(color: cs.primary.withValues(alpha: 0.5)) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$day',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    color: cs.onSurface)),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasR) _dot(AppColors.accent2),
                if (hasP) _dot(AppColors.danger),
                if (!hasR && !hasP && hasSettled) _dot(cs.outlineVariant),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}
