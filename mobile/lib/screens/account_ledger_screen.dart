// Account ledger (passbook) — a single account's statement: every transaction
// that moves this account, with a running balance per row that starts from the
// account's opening balance and ends at its current balance. Rows accrue
// oldest→newest; the list is shown newest first. Ports src/pages/AccountLedger.tsx.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../services/statement_cycle.dart';
import '../state/data_controller.dart';
import 'transaction_detail.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

// Human-readable labels for transaction line types (mirrors src/lib/lineTypes.ts).
const lineTypeLabel = <String, String>{
  'income': 'Income',
  'expense': 'Expense',
  'transfer_out': 'Transfer out',
  'transfer_in': 'Transfer in',
  'borrow': 'Borrow',
  'lend': 'Lend',
  'repayment': 'Repayment',
  'fee': 'Fee',
  'interest_income': 'Interest income',
  'interest_expense': 'Interest expense',
  'tax': 'Tax / GST',
};

String _labelFor(String type) => lineTypeLabel[type] ?? type;

class _LedgerRow {
  final DateTime date;
  final String description;
  final String types;
  final double delta;
  final double balance;
  final Txn txn;
  _LedgerRow(this.date, this.description, this.types, this.delta, this.balance, this.txn);
}

class AccountLedgerScreen extends StatefulWidget {
  final String accountId;
  const AccountLedgerScreen({super.key, required this.accountId});

  @override
  State<AccountLedgerScreen> createState() => _AccountLedgerScreenState();
}

class _AccountLedgerScreenState extends State<AccountLedgerScreen> {
  DateTime? _from;
  DateTime? _to;

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _from = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _to = DateTime(picked.year, picked.month, picked.day));
  }

  bool _inRange(DateTime date) {
    if (_from != null && date.isBefore(_from!)) return false;
    // To-date inclusive: keep everything strictly before the next day.
    if (_to != null && !date.isBefore(_to!.add(const Duration(days: 1)))) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canExport = ws.can('reports.export');
    final account = data.accountsById[widget.accountId];

    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ledger')),
        body: const EmptyView(title: 'Account not found'),
      );
    }

    // Build the running-balance statement: only transactions that move this
    // account, oldest first, accruing from the opening balance over ALL of them.
    // The date filter is applied only for display so the balance stays correct.
    final byDebt = data.debtsById;
    final mine = <MapEntry<double, Txn>>[];
    for (final t in data.transactions) {
      final delta = accountDeltas(t, byDebt)[widget.accountId];
      if (delta == null || delta == 0) continue;
      mine.add(MapEntry(delta, t));
    }
    mine.sort((a, b) => a.value.date.compareTo(b.value.date)); // oldest first

    var running = account.openingBalance;
    final filtered = <_LedgerRow>[]; // chronological, within the date filter
    for (final e in mine) {
      running = roundMoney(running + e.key);
      if (!_inRange(e.value.date)) continue;
      final types = <String>{for (final l in e.value.lines) _labelFor(l.type)}.join(', ');
      filtered.add(_LedgerRow(
        e.value.date,
        e.value.note?.isNotEmpty == true ? e.value.note! : '—',
        types,
        e.key,
        running,
        e.value,
      ));
    }
    final display = filtered.reversed.toList(); // newest first

    final balance = data.balanceOf(widget.accountId);
    final hasFilter = _from != null || _to != null;

    final typeLabel =
        account.type == 'cash' ? 'Cash' : (account.type == 'credit_card' ? 'Credit card' : 'Bank');
    final masked = account.cardLast4 != null && account.cardLast4!.isNotEmpty
        ? '···· ${account.cardLast4}'
        : (account.accountNumber != null && account.accountNumber!.length >= 4
            ? '····${account.accountNumber!.substring(account.accountNumber!.length - 4)}'
            : '');
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(account.name, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    typeLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                  ),
                ),
                if (masked.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(masked, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ],
            ),
          ],
        ),
        actions: [
          if (canExport && filtered.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Export CSV',
              onPressed: () => _exportCsv(context, account.name, filtered),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                    child: _SummaryTile(
                        label: 'Opening balance', amount: account.openingBalance, currency: currency)),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryTile(
                    label: 'Current balance',
                    amount: balance,
                    currency: currency,
                    text: accountBalanceLabel(account.type, balance, currency),
                    color: balance < 0 ? AppColors.danger : null,
                  ),
                ),
              ],
            ),
          ),
          if (account.hasBillingCycle)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: StatementSummary(
                card: account,
                txns: data.transactions,
                debtsById: data.debtsById,
                currency: currency,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(_from != null ? formatDate(_from!) : 'From', overflow: TextOverflow.ellipsis),
                    onPressed: _pickFrom,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(_to != null ? formatDate(_to!) : 'To', overflow: TextOverflow.ellipsis),
                    onPressed: _pickTo,
                  ),
                ),
                if (hasFilter)
                  TextButton(
                    onPressed: () => setState(() {
                      _from = null;
                      _to = null;
                    }),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: display.isEmpty
                ? EmptyView(
                    title: 'No entries',
                    hint: hasFilter
                        ? 'No transactions in this date range.'
                        : 'Transactions that move this account will appear here.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: display.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = display[i];
                      final cs = Theme.of(context).colorScheme;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 2),
                        // Ledger rows open the transaction's detail sheet.
                        onTap: () => showTransactionDetail(context, r.txn),
                        title: Text(r.description),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(formatDate(r.date)),
                            if (r.types.isNotEmpty)
                              Text(
                                r.types,
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatMoney(r.delta, currency),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: r.delta > 0 ? AppColors.accent2 : AppColors.danger,
                              ),
                            ),
                            Text(
                              formatMoney(r.balance, currency),
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, String accountName, List<_LedgerRow> rows) async {
    // CSV in chronological order (oldest first) reads like a statement.
    final buf = StringBuffer('Date,Description,Type,Amount,Balance\n');
    for (final r in rows) {
      buf.writeln([
        formatDate(r.date),
        r.description,
        r.types,
        r.delta.toString(),
        r.balance.toString(),
      ].map(_csvField).join(','));
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/ledger-${accountName.replaceAll(RegExp(r'\s+'), '-').toLowerCase()}.csv');
    await file.writeAsString(buf.toString());
    await Share.shareXFiles(
      [XFile(file.path, name: 'ledger-$accountName.csv')],
    );
  }

  static String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final double amount;
  final String currency;
  final Color? color;
  final String? text;
  const _SummaryTile(
      {required this.label, required this.amount, required this.currency, this.color, this.text});

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
            Text(
              text ?? formatMoney(amount, currency),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color ?? cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card's live bill: what was owed when the statement was drawn, when it
/// has to be paid, and how much of the limit is gone.
///
/// It reads the cycle rather than the due, so it says something useful from the
/// moment the cycle is set up — before the sync has raised anything, and on a
/// card whose bill you have already dismissed.
class StatementSummary extends StatelessWidget {
  final Account card;
  final List<Txn> txns;
  final Map<String, Debt> debtsById;
  final String currency;

  /// Injectable so the countdown can be asserted against a fixed day.
  final DateTime? now;

  const StatementSummary({
    super.key,
    required this.card,
    required this.txns,
    required this.debtsById,
    required this.currency,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = this.now ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cycle = latestStatement(card, now);
    if (cycle == null) return const SizedBox.shrink();

    final owed = statementOutstanding(card, txns, debtsById, cycle.statementDate);
    final days = cycle.paymentDue.difference(today).inDays;
    final settled = owed <= 0.005;

    final (String status, Color tone) = switch (days) {
      _ when settled => ('Nothing to pay', cs.onSurfaceVariant),
      < 0 => ('Overdue by ${-days} ${-days == 1 ? 'day' : 'days'}', AppColors.danger),
      0 => ('Due today', AppColors.warning),
      <= 3 => ('Due in $days ${days == 1 ? 'day' : 'days'}', AppColors.warning),
      _ => ('Due in $days days', cs.onSurfaceVariant),
    };

    // Spend since the statement is next month's bill, not this one's — worth
    // saying, because the card's current balance shows the two added together.
    final sinceStatement = roundMoney(statementOutstanding(card, txns, debtsById, today) - owed);

    final limit = card.creditLimit;
    final usedNow = statementOutstanding(card, txns, debtsById, today);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Statement of ${formatDate(cycle.statementDate)}',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              settled ? formatMoney(0, currency) : formatMoney(owed, currency),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              settled ? status : '$status · by ${formatDate(cycle.paymentDue)}',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: tone),
            ),
            if (sinceStatement.abs() > 0.005) ...[
              const SizedBox(height: 10),
              Text(
                '${formatMoney(sinceStatement, currency)} spent since, on the next bill',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
            if (limit != null && limit > 0) ...[
              const SizedBox(height: 14),
              _LimitBar(used: usedNow, limit: limit, currency: currency),
            ],
          ],
        ),
      ),
    );
  }
}

class _LimitBar extends StatelessWidget {
  final double used;
  final double limit;
  final String currency;
  const _LimitBar({required this.used, required this.limit, required this.currency});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fraction = (used / limit).clamp(0.0, 1.0);
    final percent = (fraction * 100).round();
    final tone = percent >= 90 ? AppColors.danger : (percent >= 70 ? AppColors.warning : cs.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$percent% of ${formatMoney(limit, currency)} used',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            Text(
              '${formatMoney(roundMoney(limit - used), currency)} left',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(tone),
          ),
        ),
      ],
    );
  }
}
