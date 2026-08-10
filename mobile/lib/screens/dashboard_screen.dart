import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  PeriodKind period = PeriodKind.month;

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final data = context.watch<DataController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final fyStart = ws.activeWorkspace?.fyStartMonth ?? 4;
    final now = DateTime.now();
    final range = resolvePeriod(period, now, fyStart);

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

    final topSpend =
        spendByCategoryInRange(data.transactions, data.categories, range.start, range.end).take(6).toList();

    final recent = [...data.transactions]..sort((a, b) => b.date.compareTo(a.date));
    final recentTop = recent.take(6).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _periodSelector(),
        const SizedBox(height: 12),
        _NetWorthHero(current: current, delta: delta, series: nwSeries, currency: currency),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: StatCard(label: 'Income', amount: trend.income, currency: currency, tone: StatTone.success, icon: Icons.arrow_upward)),
            const SizedBox(width: 12),
            Expanded(child: StatCard(label: 'Expense', amount: trend.expense, currency: currency, tone: StatTone.danger, icon: Icons.arrow_downward)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: StatCard(label: 'Net', amount: trend.net, currency: currency, tone: trend.net >= 0 ? StatTone.success : StatTone.danger)),
            const SizedBox(width: 12),
            Expanded(child: StatCard(label: 'In accounts', amount: totalInAccounts, currency: currency, icon: Icons.account_balance_wallet_outlined)),
          ],
        ),
        const SizedBox(height: 12),
        if (held.abs() > 0.005)
          StatCard(label: 'Held for others (Custodial)', amount: held, currency: currency, icon: Icons.people_outline),
        if (held.abs() > 0.005) const SizedBox(height: 12),
        SectionCard(
          title: 'Spend by category',
          child: topSpend.isEmpty
              ? Text('No spend recorded.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (final c in topSpend) _spendRow(c, topSpend.first.amount, currency),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Recent transactions',
          child: recentTop.isEmpty
              ? Text('No transactions yet.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (final t in recentTop)
                      Padding(
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
                  ],
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _periodSelector() {
    return Align(
      alignment: Alignment.centerRight,
      child: DropdownButton<PeriodKind>(
        value: period,
        underline: const SizedBox.shrink(),
        items: [
          for (final p in [PeriodKind.week, PeriodKind.month, PeriodKind.year, PeriodKind.fy])
            DropdownMenuItem(value: p, child: Text(periodLabels[p]!)),
        ],
        onChanged: (v) => setState(() => period = v ?? PeriodKind.month),
      ),
    );
  }

  Widget _spendRow(CategorySpend c, double max, String currency) {
    final ratio = max > 0 ? (c.amount / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
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
    );
  }
}

class _NetWorthHero extends StatelessWidget {
  final double current;
  final double delta;
  final List<NetWorthPoint> series;
  final String currency;
  const _NetWorthHero({required this.current, required this.delta, required this.series, required this.currency});

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
                      Text('${delta > 0 ? '+' : '−'}${formatMoney(delta.abs(), currency)} · 6 months',
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
