// Reports (§6.9) — ports src/pages/Reports.tsx. FY-scoped insights, tax summary,
// spend by category, and by-contact totals. CSV export gated by reports.export.

import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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
                    allTxns: data.transactions,
                    range: range,
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
                  ),
                  _ContactTab(
                    txns: fyTxns,
                    contactsById: data.contactsById,
                    fy: fy,
                    currency: currency,
                    canExport: canExport,
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
  final List<Txn> allTxns;
  final ({DateTime start, DateTime end}) range;
  final String currency;
  const _InsightsTab({
    required this.txns,
    required this.accounts,
    required this.debts,
    required this.allTxns,
    required this.range,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
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
    final net = roundMoney(income - expense);
    final savingsRate = income > 0 ? (net / income * 100).round() : 0;

    final nwSeries = netWorthSeries(accounts, debts, allTxns, range.start, range.end);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: StatCard(label: 'Income', amount: income, currency: currency, tone: StatTone.success, icon: Icons.arrow_upward)),
            const SizedBox(width: 12),
            Expanded(child: StatCard(label: 'Expense', amount: expense, currency: currency, tone: StatTone.danger, icon: Icons.arrow_downward)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: StatCard(label: 'Net', amount: net, currency: currency, tone: net >= 0 ? StatTone.success : StatTone.danger)),
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
        const SizedBox(height: 24),
      ],
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

class _TaxTab extends StatelessWidget {
  final List<Txn> txns;
  final String fy;
  final String currency;
  final bool canExport;
  const _TaxTab({required this.txns, required this.fy, required this.currency, required this.canExport});

  @override
  Widget build(BuildContext context) {
    final heads = <String>[];
    final taxableByHead = <String, double>{};
    final tdsByHead = <String, double>{};
    var totalTaxable = 0.0;
    var totalTds = 0.0;

    for (final t in txns) {
      for (final line in t.lines) {
        final tax = line.tax;
        if (tax == null || tax['taxable'] != true) continue;
        final head = (tax['head'] as String?) ?? 'other';
        final tds = (tax['tdsAmount'] is num) ? (tax['tdsAmount'] as num).toDouble() : 0.0;
        if (!taxableByHead.containsKey(head)) heads.add(head);
        taxableByHead[head] = (taxableByHead[head] ?? 0) + line.amount;
        tdsByHead[head] = (tdsByHead[head] ?? 0) + tds;
        totalTaxable += line.amount;
        totalTds += tds;
      }
    }
    totalTaxable = roundMoney(totalTaxable);
    totalTds = roundMoney(totalTds);

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
                  const ['head', 'taxableAmount', 'tdsAmount'],
                  [
                    for (final h in heads)
                      [h, roundMoney(taxableByHead[h] ?? 0), roundMoney(tdsByHead[h] ?? 0)],
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
                    title: Text(h, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text('TDS ${formatMoney(roundMoney(tdsByHead[h] ?? 0), currency)}'),
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
  const _CategoryTab({
    required this.txns,
    required this.categories,
    required this.range,
    required this.fy,
    required this.currency,
    required this.canExport,
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
  const _ContactTab({
    required this.txns,
    required this.contactsById,
    required this.fy,
    required this.currency,
    required this.canExport,
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
        SectionCard(
          title: 'By contact',
          child: Column(
            children: [
              for (final id in order)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(nameOf(id)),
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
