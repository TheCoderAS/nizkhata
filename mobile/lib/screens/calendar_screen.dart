import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import 'due_form.dart';
import 'split_transaction_form.dart';

/// Per-day due totals for one month.
typedef _MonthDues = ({
  Map<int, double> receivable,
  Map<int, double> payable,
  Set<int> settled,
});

/// Month shown on swipe page [page], counting from [base] at [initialPage].
/// Dart's DateTime normalizes out-of-range months, so this rolls over years.
DateTime calendarMonthForPage(DateTime base, int page, int initialPage) =>
    DateTime(base.year, base.month + (page - initialPage));

/// Week rows needed to lay [month] out on a Sunday-first grid (4 to 6).
int calendarGridRows(DateTime month) {
  final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  return ((firstWeekday + daysInMonth) / 7).ceil();
}

/// Cash-flow calendar — a month grid with dues marked on their day as coloured
/// stripes (green receivable / red payable, settled muted), the way a calendar
/// app marks event days. Swipe left/right to move between months; tapping a day
/// opens the dues-day drill-down.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // Pages are months either side of the month the screen opened on; the initial
  // index leaves ~100 years of swiping in both directions.
  static const _initialPage = 1200;
  static const _pageCount = 2401;

  final DateTime _baseMonth = DateTime(DateTime.now().year, DateTime.now().month);
  late final PageController _pager = PageController(initialPage: _initialPage);
  late DateTime _month = _baseMonth;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) =>
      calendarMonthForPage(_baseMonth, page, _initialPage);

  void _step(int delta) {
    final page = (_pager.page ?? _initialPage.toDouble()).round() + delta;
    _pager.animateToPage(
      page.clamp(0, _pageCount - 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Open amounts per day of [month], and the days whose dues are all settled.
  _MonthDues _duesFor(DataController data, DateTime month) {
    final receivable = <int, double>{};
    final payable = <int, double>{};
    final settled = <int>{};
    for (final d in data.dues) {
      if (d.dueDate.year != month.year || d.dueDate.month != month.month) continue;
      final st = dueStatusFromSettled(d, data.settledOf(d.id));
      if (st == 'cancelled') continue;
      final remaining = d.amount - data.settledOf(d.id);
      if (st == 'settled' || remaining <= 0.005) {
        settled.add(d.dueDate.day);
        continue;
      }
      if (d.direction == 'receivable') {
        receivable[d.dueDate.day] = (receivable[d.dueDate.day] ?? 0) + remaining;
      } else {
        payable[d.dueDate.day] = (payable[d.dueDate.day] ?? 0) + remaining;
      }
    }
    return (receivable: receivable, payable: payable, settled: settled);
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();

    // Totals for the month currently on screen (drives the footer legend).
    final visible = _duesFor(data, _month);
    var monthIn = 0.0, monthOut = 0.0;
    visible.receivable.forEach((_, v) => monthIn += v);
    visible.payable.forEach((_, v) => monthOut += v);
    final isThisMonth = _month.year == today.year && _month.month == today.month;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          if (!isThisMonth)
            TextButton(
              onPressed: () => _pager.animateToPage(
                _initialPage,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
              ),
              child: const Text('Today'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous month',
                  onPressed: () => _step(-1),
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
                  tooltip: 'Next month',
                  onPressed: () => _step(1),
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
            child: PageView.builder(
              controller: _pager,
              itemCount: _pageCount,
              onPageChanged: (p) => setState(() => _month = _monthForPage(p)),
              itemBuilder: (context, page) {
                final month = _monthForPage(page);
                return _monthGrid(context, month, _duesFor(data, month), today, currency);
              },
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
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _monthGrid(
    BuildContext context,
    DateTime month,
    _MonthDues dues,
    DateTime today,
    String currency,
  ) {
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7; // Sun = 0
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final rows = calendarGridRows(month);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (var r = 0; r < rows; r++)
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(
                      child: _dayCell(
                        context,
                        month,
                        r * 7 + c - firstWeekday + 1,
                        daysInMonth,
                        dues,
                        today,
                        currency,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayCell(
    BuildContext context,
    DateTime month,
    int day,
    int daysInMonth,
    _MonthDues dues,
    DateTime today,
    String currency,
  ) {
    if (day < 1 || day > daysInMonth) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final isToday =
        today.year == month.year && today.month == month.month && today.day == day;
    final r = dues.receivable[day];
    final p = dues.payable[day];
    final hasSettled = dues.settled.contains(day);
    final date = DateTime(month.year, month.month, day);

    // Colour alone can't carry the meaning — spell the day out for screen
    // readers, since the stripes are the only visual marker.
    final parts = <String>[
      if (r != null) 'to receive ${formatMoney(r, currency)}',
      if (p != null) 'to pay ${formatMoney(p, currency)}',
      if (r == null && p == null && hasSettled) 'settled dues',
    ];
    final label = '${DateFormat('d MMMM').format(date)}'
        '${parts.isEmpty ? '' : ', ${parts.join(', ')}'}';

    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        // Every day is actionable, not just the ones carrying dues: tapping
        // opens what you can do on that date.
        onTap: () => _openDayActions(context, date),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Date sits at the top of the cell, today ringed in a filled
              // circle, with the day's stripes stacked beneath it.
              SizedBox(
                height: 22,
                child: Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? BoxDecoration(color: cs.primary, shape: BoxShape.circle)
                        : null,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                        color: isToday ? cs.onPrimary : cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              if (r != null) _stripe(AppColors.accent2),
              if (p != null) _stripe(AppColors.danger),
              if (r == null && p == null && hasSettled) _stripe(cs.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// What you can do with one day: add to it, or look at what's already there.
  /// Counts come along so the sheet says whether looking is worth it.
  void _openDayActions(BuildContext context, DateTime date) {
    final data = context.read<DataController>();
    final ws = context.read<WorkspaceController>();
    final iso = '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    bool sameDay(DateTime d) =>
        d.year == date.year && d.month == date.month && d.day == date.day;
    final dueCount = data.dues.where((d) => sameDay(d.dueDate)).length;
    final txnCount = data.transactions.where((t) => sameDay(t.date)).length;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(DateFormat('EEEE, d MMMM yyyy').format(date),
                  style: Theme.of(sheetCtx).textTheme.titleMedium),
            ),
            if (ws.can('transactions.create'))
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Add transaction'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  showSplitTransactionForm(context, initialDate: date);
                },
              ),
            if (ws.can('dues.manage'))
              ListTile(
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('Add due'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  showDueForm(context, initialDate: date);
                },
              ),
            if (ws.can('transactions.view'))
              ListTile(
                enabled: txnCount > 0,
                leading: const Icon(Icons.list_alt_outlined),
                title: const Text('View transactions'),
                subtitle: Text(txnCount == 0
                    ? 'Nothing recorded on this day'
                    : '$txnCount on this day'),
                onTap: txnCount == 0
                    ? null
                    : () {
                        Navigator.pop(sheetCtx);
                        context.push('/txns?date=$iso');
                      },
              ),
            if (ws.can('dues.view'))
              ListTile(
                enabled: dueCount > 0,
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('View dues'),
                subtitle: Text(
                    dueCount == 0 ? 'Nothing due on this day' : '$dueCount on this day'),
                onTap: dueCount == 0
                    ? null
                    : () {
                        Navigator.pop(sheetCtx);
                        context.push('/dues-day?date=$iso');
                      },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _stripe(Color c) => Container(
        height: 4,
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
      );
}
