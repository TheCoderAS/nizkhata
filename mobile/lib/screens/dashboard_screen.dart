import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import 'transaction_detail.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  PeriodKind period = PeriodKind.month;
  DateTime _customStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _customEnd = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final data = context.watch<DataController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final fyStart = ws.activeWorkspace?.fyStartMonth ?? 4;
    final canViewTxns = ws.can('transactions.view');
    final now = DateTime.now();
    final range = period == PeriodKind.custom
        ? (
            start: DateTime(_customStart.year, _customStart.month, _customStart.day),
            // End is inclusive: extend to the start of the following day.
            end: DateTime(_customEnd.year, _customEnd.month, _customEnd.day).add(const Duration(days: 1)),
          )
        : resolvePeriod(period, now, fyStart);

    final trend = trendSeries(data.transactions, range.start, range.end);
    final totalInAccounts =
        data.accounts.fold<double>(0, (s, a) => s + data.balanceOf(a.id));
    final held = custodialHeld(data.debts, data.transactions);

    // Net worth (trailing 6 months).
    final nwStart = DateTime(now.year, now.month - 5, 1);
    final nwEnd = DateTime(now.year, now.month + 1, 1);
    final nwSeries = netWorthSeries(data.accounts, data.debts, data.transactions, nwStart, nwEnd);
    final current = nwSeries.isNotEmpty ? nwSeries.last.netWorth : 0.0;
    final first = nwSeries.isNotEmpty ? nwSeries.first.netWorth : 0.0;
    final delta = current - first;
    final int? nwPct = first != 0 ? (delta / first.abs() * 100).round() : null;

    final topSpend =
        spendByCategoryInRange(data.transactions, data.categories, range.start, range.end).take(6).toList();

    // Upcoming dues within the selected period (open/partial), soonest first.
    final upcoming = data.dues.where((d) {
      final status = dueStatusFromSettled(d, data.settledOf(d.id));
      if (status != 'open' && status != 'partial') return false;
      final dd = d.dueDate;
      return !dd.isBefore(range.start) && dd.isBefore(range.end);
    }).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final upcomingTop = upcoming.take(5).toList();

    final budgetRows =
        budgetProgress(data.budgets, data.transactions, data.categoriesById, fyStart).take(4).toList();

    final recent = [...data.transactions]..sort((a, b) => b.date.compareTo(a.date));
    final recentTop = recent.take(6).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _periodSelector(),
        if (period == PeriodKind.custom) ...[
          const SizedBox(height: 12),
          _customRangePickers(),
        ],
        const SizedBox(height: 12),
        _NetWorthHero(current: current, delta: delta, pct: nwPct, series: nwSeries, currency: currency),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _trendStat(
                label: 'Income',
                amount: trend.income,
                currency: currency,
                tone: StatTone.success,
                icon: Icons.arrow_upward,
                spark: [for (final b in trend.buckets) b.income],
                sparkColor: AppColors.accent2,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _trendStat(
                label: 'Expense',
                amount: trend.expense,
                currency: currency,
                tone: StatTone.danger,
                icon: Icons.arrow_downward,
                spark: [for (final b in trend.buckets) b.expense],
                sparkColor: AppColors.danger,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _trendStat(
                label: 'Net',
                amount: trend.net,
                currency: currency,
                tone: trend.net >= 0 ? StatTone.success : StatTone.danger,
                spark: [for (final b in trend.buckets) b.net],
                sparkColor: trend.net >= 0 ? AppColors.accent2 : AppColors.danger,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: StatCard(label: 'In accounts', amount: totalInAccounts, currency: currency, icon: Icons.account_balance_wallet_outlined)),
          ],
        ),
        const SizedBox(height: 12),
        StatCard(label: 'Held for others (Custodial)', amount: held, currency: currency, icon: Icons.people_outline),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Upcoming dues',
          trailing: _seeAll('/dues'),
          child: upcomingTop.isEmpty
              ? Text('Nothing due.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (final d in upcomingTop) _dueRow(d, currency),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        if (budgetRows.isNotEmpty) ...[
          SectionCard(
            title: 'Budgets',
            trailing: _seeAll('/budgets'),
            child: Column(
              children: [
                for (final p in budgetRows) _budgetRow(p, currency),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        SectionCard(
          title: 'Spend by category',
          trailing: _seeAll('/reports'),
          child: topSpend.isEmpty
              ? Text('No spend recorded.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (final c in topSpend)
                      _spendRow(
                        c,
                        topSpend.first.amount,
                        currency,
                        onTap: canViewTxns ? () => context.push('/txns?category=${c.id}') : null,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Recent transactions',
          trailing: _seeAll('/transactions'),
          child: recentTop.isEmpty
              ? Text('No transactions yet.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (final t in recentTop)
                      InkWell(
                        onTap: () => showTransactionDetail(context, t),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.note?.isNotEmpty == true ? t.note! : 'Transaction',
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text(formatDate(t.date),
                                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              Text(
                                formatMoney(t.totalAmount, currency),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: t.totalAmount < 0 ? AppColors.danger : AppColors.accent2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _seeAll(String route) => TextButton(
        onPressed: () => context.go(route),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: const Text('See all'),
      );

  Widget _periodSelector() {
    const short = {
      PeriodKind.week: 'Week',
      PeriodKind.month: 'Month',
      PeriodKind.year: 'Year',
      PeriodKind.fy: 'FY',
      PeriodKind.custom: 'Custom',
    };
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<PeriodKind>(
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll(
            Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        segments: [
          for (final p in [PeriodKind.week, PeriodKind.month, PeriodKind.year, PeriodKind.fy, PeriodKind.custom])
            ButtonSegment(value: p, label: Text(short[p]!)),
        ],
        selected: {period},
        onSelectionChanged: (s) => setState(() => period = s.first),
      ),
    );
  }

  Widget _customRangePickers() {
    return Row(
      children: [
        Expanded(child: _dateField('From', _customStart, (d) => setState(() => _customStart = d))),
        const SizedBox(width: 12),
        Expanded(child: _dateField('To', _customEnd, (d) => setState(() => _customEnd = d))),
      ],
    );
  }

  Widget _dateField(String label, DateTime value, ValueChanged<DateTime> onPicked) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 44),
          ),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) onPicked(picked);
          },
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(formatDate(value), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _trendStat({
    required String label,
    required double amount,
    required String currency,
    required StatTone tone,
    required List<double> spark,
    required Color sparkColor,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatCard(label: label, amount: amount, currency: currency, tone: tone, icon: icon),
        const SizedBox(height: 6),
        _sparkline(spark, sparkColor),
      ],
    );
  }

  Widget _sparkline(List<double> values, Color color) {
    if (values.length < 2) return const SizedBox(height: 28);
    return SizedBox(
      height: 28,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
              isCurved: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dueRow(Due d, String currency) {
    final cs = Theme.of(context).colorScheme;
    final receivable = d.direction == 'receivable';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(d.title.isNotEmpty ? d.title : 'Due',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (receivable ? AppColors.accent2 : AppColors.danger).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        d.direction,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: receivable ? AppColors.accent2 : AppColors.danger),
                      ),
                    ),
                  ],
                ),
                Text(formatDate(d.dueDate), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Text(formatMoney(d.amount, currency), style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _budgetRow(BudgetProgress p, String currency) {
    final cs = Theme.of(context).colorScheme;
    final Color barColor =
        p.ratio > 1 ? AppColors.danger : (p.ratio > 0.8 ? Colors.orange : cs.primary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(p.categoryName, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(
                '${formatMoney(p.spent, currency)} / ${formatMoney(p.limit, currency)}',
                style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: p.ratio > 1 ? AppColors.danger : cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: p.ratio.clamp(0.0, 1.0).toDouble(),
              minHeight: 7,
              color: barColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _spendRow(CategorySpend c, double max, String currency, {VoidCallback? onTap}) {
    final double ratio = max > 0 ? (c.amount / max).clamp(0.0, 1.0).toDouble() : 0.0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(formatMoney(c.amount, currency), style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: ratio, minHeight: 7),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetWorthHero extends StatelessWidget {
  final double current;
  final double delta;
  final int? pct;
  final List<NetWorthPoint> series;
  final String currency;
  const _NetWorthHero(
      {required this.current, required this.delta, required this.pct, required this.series, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: brandGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Net worth', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(formatMoney(current, currency),
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                if (delta.abs() > 0.005) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(delta > 0 ? Icons.arrow_upward : Icons.arrow_downward, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                          '${delta > 0 ? '+' : '−'}${formatMoney(delta.abs(), currency)}'
                          '${pct != null ? ' (${pct! > 0 ? '+' : ''}$pct%)' : ''} · 6 months',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (series.length > 1)
            SizedBox(
              width: 96,
              height: 48,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < series.length; i++) FlSpot(i.toDouble(), series[i].netWorth),
                      ],
                      isCurved: true,
                      color: Colors.white,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: Colors.white.withValues(alpha: 0.2)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
