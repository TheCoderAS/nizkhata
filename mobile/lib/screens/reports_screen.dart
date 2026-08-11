// Reports (§6.9) — ports src/pages/Reports.tsx. FY-scoped insights, tax summary,
// spend by category, and by-contact totals. CSV export gated by reports.export.

import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

// Palette for donut slices (top 6 + Other).
const _donutColors = <Color>[
  AppColors.brand,
  AppColors.accent2,
  Color(0xFFF59E0B), // amber
  Color(0xFFEF4444), // red
  Color(0xFF06B6D4), // cyan
  Color(0xFF8B5CF6), // violet
  Color(0xFF94A3B8), // slate (Other)
];

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String? _fy;

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final data = context.watch<DataController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final fyStart = ws.activeWorkspace?.fyStartMonth ?? 4;
    final canExport = ws.can('reports.export');
    final canViewTxns = ws.can('transactions.view');

    // Distinct FYs present in the data, plus the current one, sorted desc.
    final fySet = <String>{financialYearOf(DateTime.now(), fyStart)};
    for (final t in data.transactions) {
      if (t.financialYear.isNotEmpty) fySet.add(t.financialYear);
    }
    final fyOptions = fySet.toList()..sort((a, b) => b.compareTo(a));
    final fy = (_fy != null && fyOptions.contains(_fy)) ? _fy! : fyOptions.first;

    // Date range for the selected FY string (e.g. "2026-27" or "2026").
    final startYear = int.parse(fy.split('-')[0]);
    final range = financialYearRange(DateTime(startYear, fyStart, 1), fyStart);

    final fyTxns = data.transactions.where((t) => t.financialYear == fy).toList();

    // Prior FY string (one year before the selected FY) for period-over-period
    // deltas + top movers. Mirrors web `prevFy`.
    final prevStartYear = startYear - 1;
    final prevFy = fyStart == 1
        ? '$prevStartYear'
        : '$prevStartYear-${((prevStartYear + 1) % 100).toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButton<String>(
              value: fy,
              underline: const SizedBox.shrink(),
              items: [
                for (final f in fyOptions)
                  DropdownMenuItem(value: f, child: Text('FY $f')),
              ],
              onChanged: (v) => setState(() => _fy = v),
            ),
          ),
        ],
      ),
      body: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Insights'),
                Tab(text: 'Tax'),
                Tab(text: 'By category'),
                Tab(text: 'By contact'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _InsightsTab(
                    txns: fyTxns,
                    accounts: data.accounts,
                    debts: data.debts,
                    categories: data.categories,
                    allTxns: data.transactions,
                    range: range,
                    prevFy: prevFy,
                    currency: currency,
                  ),
                  _TaxTab(txns: fyTxns, fy: fy, currency: currency, canExport: canExport),
                  _CategoryTab(
                    txns: data.transactions,
                    categories: data.categories,
                    range: range,
                    fy: fy,
                    currency: currency,
                    canExport: canExport,
                    canViewTxns: canViewTxns,
                  ),
                  _ContactTab(
                    txns: fyTxns,
                    contactsById: data.contactsById,
                    fy: fy,
                    currency: currency,
                    canExport: canExport,
                    canViewTxns: canViewTxns,
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

// ---- CSV export -------------------------------------------------------------

String _csvCell(Object? v) {
  final s = v?.toString() ?? '';
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

Future<void> _exportCsv(String fileName, List<String> header, List<List<Object?>> rows) async {
  final buf = StringBuffer();
  buf.writeln(header.map(_csvCell).join(','));
  for (final r in rows) {
    buf.writeln(r.map(_csvCell).join(','));
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(buf.toString());
  await Share.shareXFiles([XFile(file.path)]);
}

Widget _exportButton(VoidCallback onPressed) {
  return Align(
    alignment: Alignment.centerRight,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.download, size: 18),
      label: const Text('Export CSV'),
    ),
  );
}

// ---- Insights ---------------------------------------------------------------

class _InsightsTab extends StatelessWidget {
  final List<Txn> txns;
  final List<Account> accounts;
  final List<Debt> debts;
  final List<AppCategory> categories;
  final List<Txn> allTxns;
  final ({DateTime start, DateTime end}) range;
  final String prevFy;
  final String currency;
  const _InsightsTab({
    required this.txns,
    required this.accounts,
    required this.debts,
    required this.categories,
    required this.allTxns,
    required this.range,
    required this.prevFy,
    required this.currency,
  });

  // Income/expense/net totals for a set of FY-scoped transactions.
  static ({double income, double expense, double net}) _totals(List<Txn> txns) {
    var income = 0.0;
    var expense = 0.0;
    for (final t in txns) {
      for (final line in t.lines) {
        switch (line.type) {
          case 'income':
          case 'interest_income':
            income += line.amount;
            break;
          case 'expense':
          case 'interest_expense':
          case 'fee':
          case 'tax':
            expense += line.amount;
            break;
        }
      }
    }
    income = roundMoney(income);
    expense = roundMoney(expense);
    return (income: income, expense: expense, net: roundMoney(income - expense));
  }

  @override
  Widget build(BuildContext context) {
    final cur = _totals(txns);
    final income = cur.income;
    final expense = cur.expense;
    final net = cur.net;
    final savingsRate = income > 0 ? (net / income * 100).round() : 0;

    // Prior-FY totals for period-over-period %-deltas (filter by stored FY).
    final prev = _totals(allTxns.where((t) => t.financialYear == prevFy).toList());

    final nwSeries = netWorthSeries(accounts, debts, allTxns, range.start, range.end);
    final trend = trendSeries(allTxns, range.start, range.end);
    final catTrend = _categoryTrendSeries(allTxns, categories, range.start, range.end);

    // Top movers: per-category spend change vs the prior FY. The prior range is
    // the current FY range shifted back one year.
    final curCat = spendByCategoryInRange(allTxns, categories, range.start, range.end);
    final prevRange = (
      start: DateTime(range.start.year - 1, range.start.month, 1),
      end: DateTime(range.end.year - 1, range.end.month, 1),
    );
    final prevCat = spendByCategoryInRange(allTxns, categories, prevRange.start, prevRange.end);
    final movers = _topMovers(curCat, prevCat, 6);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StatWithDelta(
                delta: _pctDelta(income, prev.income),
                higherIsGood: true,
                child: StatCard(label: 'Income', amount: income, currency: currency, tone: StatTone.success, icon: Icons.arrow_upward),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatWithDelta(
                delta: _pctDelta(expense, prev.expense),
                higherIsGood: false,
                child: StatCard(label: 'Expense', amount: expense, currency: currency, tone: StatTone.danger, icon: Icons.arrow_downward),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StatWithDelta(
                delta: _pctDelta(net, prev.net),
                higherIsGood: true,
                child: StatCard(label: 'Net', amount: net, currency: currency, tone: net >= 0 ? StatTone.success : StatTone.danger),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _PlainStatCard(label: 'Savings rate', value: '$savingsRate%')),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Net worth',
          child: nwSeries.length > 1
              ? SizedBox(height: 180, child: _NetWorthChart(series: nwSeries))
              : Text('Not enough data to plot net worth.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Income vs expense',
          child: trend.buckets.length > 1
              ? SizedBox(height: 180, child: _TrendChart(buckets: trend.buckets))
              : Text('Not enough data to plot the trend.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Spend by category over time',
          child: (catTrend.keys.isNotEmpty && catTrend.buckets.isNotEmpty)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 200, child: _CategoryTrendChart(trend: catTrend)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < catTrend.keys.length; i++)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _donutColors[i % _donutColors.length],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(catTrend.keys[i],
                                  style: TextStyle(
                                      fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                      ],
                    ),
                  ],
                )
              : Text('Not enough data to plot category spend.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Top movers',
          child: movers.isEmpty
              ? Text('Not enough history to compare.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (final m in movers)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(m.name, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 8),
                            Text(
                              '${formatMoney(m.previous, currency)} → ${formatMoney(m.current, currency)}',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${m.delta > 0 ? '+' : '−'}${formatMoney(m.delta.abs(), currency)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: m.delta > 0 ? AppColors.danger : AppColors.accent2,
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
}

// Percentage change vs a prior value. null when there's no baseline (prev == 0).
int? _pctDelta(double current, double previous) {
  if (previous == 0) return null;
  return ((current - previous) / previous.abs() * 100).round();
}

// Biggest category spend changes vs the prior FY. Mirrors web `topMovers`:
// unions current + previous categories, keeps non-zero deltas, sorts by |delta|.
List<({String id, String name, double current, double previous, double delta})> _topMovers(
    List<CategorySpend> current, List<CategorySpend> previous, int limit) {
  final prevById = {for (final c in previous) c.id: c};
  final seen = <String>{};
  final movers = <({String id, String name, double current, double previous, double delta})>[];
  for (final c in current) {
    seen.add(c.id);
    final prev = prevById[c.id]?.amount ?? 0;
    movers.add((id: c.id, name: c.name, current: c.amount, previous: prev, delta: roundMoney(c.amount - prev)));
  }
  for (final c in previous) {
    if (seen.contains(c.id)) continue;
    movers.add((id: c.id, name: c.name, current: 0, previous: c.amount, delta: roundMoney(-c.amount)));
  }
  final out = movers.where((m) => m.delta != 0).toList()
    ..sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
  return out.take(limit).toList();
}

// A stat card with a coloured prior-FY %-delta badge underneath.
class _StatWithDelta extends StatelessWidget {
  final Widget child;
  final int? delta;
  final bool higherIsGood;
  const _StatWithDelta({required this.child, required this.delta, required this.higherIsGood});

  @override
  Widget build(BuildContext context) {
    final d = delta;
    if (d == null || d == 0) return child;
    final up = d > 0;
    final good = up == higherIsGood;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '${up ? '▲' : '▼'} ${d.abs()}% vs last FY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: good ? AppColors.accent2 : AppColors.danger,
            ),
          ),
        ),
      ],
    );
  }
}

// Income (green) vs expense (red) per bucket over the FY.
class _TrendChart extends StatelessWidget {
  final List<TrendBucket> buckets;
  const _TrendChart({required this.buckets});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < buckets.length; i++) FlSpot(i.toDouble(), buckets[i].income)],
            isCurved: true,
            color: AppColors.accent2,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: [for (var i = 0; i < buckets.length; i++) FlSpot(i.toDouble(), buckets[i].expense)],
            isCurved: true,
            color: AppColors.danger,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ---- Spend by category over time -------------------------------------------

const _monthShort = <String>[
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

class _CatTrendBucket {
  final String label;
  final Map<String, double> values;
  _CatTrendBucket(this.label, this.values);
}

class _CategoryTrend {
  final List<_CatTrendBucket> buckets;
  final List<String> keys;
  _CategoryTrend(this.buckets, this.keys);
}

// Monthly stacked spend per category (top N + Other). Local port of web
// categoryTrendSeries — computed here so derive.dart stays untouched.
_CategoryTrend _categoryTrendSeries(
    List<Txn> txns, List<AppCategory> categories, DateTime start, DateTime end,
    {int topN = 5}) {
  bool isExpense(String type) =>
      type == 'expense' || type == 'interest_expense' || type == 'fee' || type == 'tax';
  final nameById = {for (final c in categories) c.id: c.name};

  // Overall spend per category over the whole range decides the top-N.
  final overall = <String, double>{};
  for (final t in txns) {
    if (t.date.isBefore(start) || !t.date.isBefore(end)) continue;
    for (final line in t.lines) {
      if (isExpense(line.type) && line.categoryId != null) {
        overall[line.categoryId!] = (overall[line.categoryId!] ?? 0) + line.amount;
      }
    }
  }
  final ranked = overall.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final topIds = ranked.take(topN).map((e) => e.key).toSet();
  final hasOther = ranked.length > topN;
  final keys = <String>[
    for (final e in ranked.take(topN)) nameById[e.key] ?? 'Uncategorized',
    if (hasOther) 'Other',
  ];

  // Month buckets across the range.
  final buckets = <_CatTrendBucket>[];
  final index = <String, int>{};
  var cursor = DateTime(start.year, start.month, 1);
  while (cursor.isBefore(end)) {
    index['${cursor.year}-${cursor.month}'] = buckets.length;
    buckets.add(_CatTrendBucket(_monthShort[cursor.month], {for (final k in keys) k: 0.0}));
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
  }

  for (final t in txns) {
    if (t.date.isBefore(start) || !t.date.isBefore(end)) continue;
    final bi = index['${t.date.year}-${t.date.month}'];
    if (bi == null) continue;
    for (final line in t.lines) {
      if (!isExpense(line.type) || line.categoryId == null) continue;
      String? key;
      if (topIds.contains(line.categoryId)) {
        key = nameById[line.categoryId] ?? 'Uncategorized';
      } else if (hasOther) {
        key = 'Other';
      }
      if (key == null) continue;
      buckets[bi].values[key] = (buckets[bi].values[key] ?? 0) + line.amount;
    }
  }
  for (final b in buckets) {
    for (final k in keys) {
      b.values[k] = roundMoney(b.values[k] ?? 0);
    }
  }
  return _CategoryTrend(buckets, keys);
}

// Stacked bar chart: one bar per month, stacked by top-N category.
class _CategoryTrendChart extends StatelessWidget {
  final _CategoryTrend trend;
  const _CategoryTrendChart({required this.trend});

  BarChartRodData _rod(_CatTrendBucket bucket) {
    var running = 0.0;
    final items = <BarChartRodStackItem>[];
    for (var k = 0; k < trend.keys.length; k++) {
      final v = bucket.values[trend.keys[k]] ?? 0;
      if (v <= 0) continue;
      items.add(BarChartRodStackItem(running, running + v, _donutColors[k % _donutColors.length]));
      running += v;
    }
    return BarChartRodData(
      toY: running,
      width: 14,
      rodStackItems: items,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= trend.buckets.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(trend.buckets[i].label,
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < trend.buckets.length; i++)
            BarChartGroupData(x: i, barRods: [_rod(trend.buckets[i])]),
        ],
      ),
    );
  }
}

class _PlainStatCard extends StatelessWidget {
  final String label;
  final String value;
  const _PlainStatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
          ],
        ),
      ),
    );
  }
}

class _NetWorthChart extends StatelessWidget {
  final List<NetWorthPoint> series;
  const _NetWorthChart({required this.series});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LineChart(
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
            color: cs.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: cs.primary.withValues(alpha: 0.15)),
          ),
        ],
      ),
    );
  }
}

// ---- Tax --------------------------------------------------------------------

// Human-readable labels for tax heads (mirrors src/lib/taxHeads.ts). Falls back
// to Title-cased key for anything unknown.
const _taxHeadLabels = <String, String>{
  'salary': 'Salary',
  'bonus': 'Bonus',
  'overtime': 'Overtime',
  'reimbursement': 'Reimbursement',
  'perquisite': 'Perquisite',
  'commission': 'Commission',
  'professional_fees': 'Professional fees',
  'rent': 'Rent',
  'interest': 'Interest',
  'dividend': 'Dividend',
  'capital_gains': 'Capital gains',
  'business': 'Business / profession',
  'other': 'Other',
  'exempt': 'Exempt',
};

String _taxHeadLabel(String head) {
  final known = _taxHeadLabels[head];
  if (known != null) return known;
  if (head.isEmpty) return head;
  return head[0].toUpperCase() + head.substring(1).replaceAll('_', ' ');
}

class _TaxTab extends StatelessWidget {
  final List<Txn> txns;
  final String fy;
  final String currency;
  final bool canExport;
  const _TaxTab({required this.txns, required this.fy, required this.currency, required this.canExport});

  @override
  Widget build(BuildContext context) {
    final taxableByHead = <String, double>{};
    final tdsByHead = <String, double>{};
    final linesByHead = <String, int>{};
    var totalTaxable = 0.0;
    var totalTds = 0.0;

    for (final t in txns) {
      for (final line in t.lines) {
        final tax = line.tax;
        if (tax == null || tax['taxable'] != true) continue;
        final head = (tax['head'] as String?) ?? 'other';
        final tds = (tax['tdsAmount'] is num) ? (tax['tdsAmount'] as num).toDouble() : 0.0;
        taxableByHead[head] = (taxableByHead[head] ?? 0) + line.amount;
        tdsByHead[head] = (tdsByHead[head] ?? 0) + tds;
        linesByHead[head] = (linesByHead[head] ?? 0) + 1;
        totalTaxable += line.amount;
        totalTds += tds;
      }
    }
    totalTaxable = roundMoney(totalTaxable);
    totalTds = roundMoney(totalTds);

    // Sort heads by taxable amount desc (mirrors web fyTaxSummary).
    final heads = taxableByHead.keys.toList()
      ..sort((a, b) => (taxableByHead[b] ?? 0).compareTo(taxableByHead[a] ?? 0));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: StatCard(label: 'Total taxable', amount: totalTaxable, currency: currency)),
            const SizedBox(width: 12),
            Expanded(child: StatCard(label: 'Total TDS', amount: totalTds, currency: currency)),
          ],
        ),
        const SizedBox(height: 12),
        if (heads.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyView(title: 'No taxable lines this FY'),
          )
        else ...[
          if (canExport) ...[
            _exportButton(() => _exportCsv(
                  'tax-summary-$fy.csv',
                  const ['Head', 'Taxable', 'TDS', 'Lines'],
                  [
                    for (final h in heads)
                      [
                        _taxHeadLabel(h),
                        roundMoney(taxableByHead[h] ?? 0),
                        roundMoney(tdsByHead[h] ?? 0),
                        linesByHead[h] ?? 0,
                      ],
                  ],
                )),
            const SizedBox(height: 8),
          ],
          SectionCard(
            title: 'By head',
            child: Column(
              children: [
                for (final h in heads)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_taxHeadLabel(h), style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      'TDS ${formatMoney(roundMoney(tdsByHead[h] ?? 0), currency)}'
                      ' · ${linesByHead[h] ?? 0} line${(linesByHead[h] ?? 0) == 1 ? '' : 's'}',
                    ),
                    trailing: Text(
                      formatMoney(roundMoney(taxableByHead[h] ?? 0), currency),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---- By category ------------------------------------------------------------

class _CategoryTab extends StatelessWidget {
  final List<Txn> txns;
  final List<AppCategory> categories;
  final ({DateTime start, DateTime end}) range;
  final String fy;
  final String currency;
  final bool canExport;
  final bool canViewTxns;
  const _CategoryTab({
    required this.txns,
    required this.categories,
    required this.range,
    required this.fy,
    required this.currency,
    required this.canExport,
    required this.canViewTxns,
  });

  @override
  Widget build(BuildContext context) {
    final byCategory = spendByCategoryInRange(txns, categories, range.start, range.end);

    if (byCategory.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: EmptyView(title: 'No spend this FY'),
      );
    }

    // Donut: top 6 + Other.
    final top = byCategory.take(6).toList();
    final rest = byCategory.skip(6).fold<double>(0, (s, c) => s + c.amount);
    final slices = <({String name, double value})>[
      for (final c in top) (name: c.name, value: c.amount),
      if (rest > 0) (name: 'Other', value: roundMoney(rest)),
    ];
    final total = roundMoney(byCategory.fold<double>(0, (s, c) => s + c.amount));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canExport) ...[
          _exportButton(() => _exportCsv(
                'spend-by-category-$fy.csv',
                const ['category', 'amount'],
                [for (final c in byCategory) [c.name, c.amount]],
              )),
          const SizedBox(height: 8),
        ],
        SectionCard(
          title: 'Spend by category',
          child: _Donut(slices: slices, total: total, centerLabel: 'Total spend', currency: currency),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Categories',
          child: Column(
            children: [
              for (final c in byCategory)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.name),
                  trailing: Text(formatMoney(c.amount, currency),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: canViewTxns
                      ? () => context.push('/transactions?category=${c.id}')
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---- By contact -------------------------------------------------------------

class _ContactTab extends StatelessWidget {
  final List<Txn> txns;
  final Map<String, Contact> contactsById;
  final String fy;
  final String currency;
  final bool canExport;
  final bool canViewTxns;
  const _ContactTab({
    required this.txns,
    required this.contactsById,
    required this.fy,
    required this.currency,
    required this.canExport,
    required this.canViewTxns,
  });

  @override
  Widget build(BuildContext context) {
    final order = <String>[];
    final received = <String, double>{};
    final paid = <String, double>{};
    for (final t in txns) {
      final cid = t.contactId;
      if (cid == null) continue;
      if (!received.containsKey(cid)) {
        order.add(cid);
        received[cid] = 0;
        paid[cid] = 0;
      }
      if (t.totalAmount >= 0) {
        received[cid] = received[cid]! + t.totalAmount;
      } else {
        paid[cid] = paid[cid]! + -t.totalAmount;
      }
    }

    if (order.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: EmptyView(title: 'No contact activity this FY'),
      );
    }

    String nameOf(String id) => contactsById[id]?.name ?? '—';

    // Donut of money paid out per contact (top 6 + Other), mirrors web contactDonut.
    final paidRanked = order.where((id) => (paid[id] ?? 0) > 0).toList()
      ..sort((a, b) => paid[b]!.compareTo(paid[a]!));
    final paidTop = paidRanked.take(6).toList();
    final paidRest = paidRanked.skip(6).fold<double>(0, (s, id) => s + paid[id]!);
    final paidSlices = <({String name, double value})>[
      for (final id in paidTop) (name: nameOf(id), value: roundMoney(paid[id]!)),
      if (paidRest > 0) (name: 'Other', value: roundMoney(paidRest)),
    ];
    final totalPaid = roundMoney(paidRanked.fold<double>(0, (s, id) => s + paid[id]!));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canExport) ...[
          _exportButton(() => _exportCsv(
                'by-contact-$fy.csv',
                const ['contact', 'received', 'paid'],
                [
                  for (final id in order)
                    [nameOf(id), roundMoney(received[id]!), roundMoney(paid[id]!)],
                ],
              )),
          const SizedBox(height: 8),
        ],
        if (paidSlices.isNotEmpty) ...[
          SectionCard(
            title: 'Paid by contact',
            child: _Donut(slices: paidSlices, total: totalPaid, centerLabel: 'Total paid', currency: currency),
          ),
          const SizedBox(height: 12),
        ],
        SectionCard(
          title: 'By contact',
          child: Column(
            children: [
              for (final id in order)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(nameOf(id)),
                  onTap: canViewTxns ? () => context.push('/transactions?contact=$id') : null,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('+ ${formatMoney(roundMoney(received[id]!), currency)}',
                          style: const TextStyle(color: AppColors.accent2, fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('- ${formatMoney(roundMoney(paid[id]!), currency)}',
                          style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600, fontSize: 13)),
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
}

// ---- Donut ------------------------------------------------------------------

class _Donut extends StatelessWidget {
  final List<({String name, double value})> slices;
  final double total;
  final String centerLabel;
  final String currency;
  const _Donut({required this.slices, required this.total, required this.centerLabel, required this.currency});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 56,
                  sections: [
                    for (var i = 0; i < slices.length; i++)
                      PieChartSectionData(
                        value: slices[i].value,
                        color: _donutColors[i % _donutColors.length],
                        title: '',
                        radius: 34,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(centerLabel, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(formatMoney(total, currency), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (var i = 0; i < slices.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _donutColors[i % _donutColors.length],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(slices[i].name, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
