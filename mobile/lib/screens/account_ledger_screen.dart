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
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

class _LedgerRow {
  final DateTime date;
  final String description;
  final double delta;
  final double balance;
  _LedgerRow(this.date, this.description, this.delta, this.balance);
}

class AccountLedgerScreen extends StatelessWidget {
  final String accountId;
  const AccountLedgerScreen({super.key, required this.accountId});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canExport = ws.can('reports.export');
    final account = data.accountsById[accountId];

    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ledger')),
        body: const EmptyView(title: 'Account not found'),
      );
    }

    // Build the running-balance statement: only transactions that move this
    // account, oldest first, accruing from the opening balance. Displayed
    // newest first (the balance stays computed from the oldest-first pass).
    final byDebt = data.debtsById;
    final mine = <MapEntry<double, Txn>>[];
    for (final t in data.transactions) {
      final delta = accountDeltas(t, byDebt)[accountId];
      if (delta == null || delta == 0) continue;
      mine.add(MapEntry(delta, t));
    }
    mine.sort((a, b) => a.value.date.compareTo(b.value.date)); // oldest first

    var running = account.openingBalance;
    final rows = <_LedgerRow>[];
    for (final e in mine) {
      running = roundMoney(running + e.key);
      rows.add(_LedgerRow(e.value.date, e.value.note?.isNotEmpty == true ? e.value.note! : '—', e.key, running));
    }
    final display = rows.reversed.toList(); // newest first

    final balance = data.balanceOf(accountId);

    return Scaffold(
      appBar: AppBar(
        title: Text('${account.name} · ledger'),
        actions: [
          if (canExport)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Export CSV',
              onPressed: () => _exportCsv(context, account.name, rows),
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
                Expanded(child: _SummaryTile(label: 'Opening balance', amount: account.openingBalance, currency: currency)),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryTile(
                    label: 'Current balance',
                    amount: balance,
                    currency: currency,
                    color: balance < 0 ? AppColors.danger : null,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: display.isEmpty
                ? const EmptyView(
                    title: 'No entries',
                    hint: 'Transactions that move this account will appear here.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: display.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = display[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 2),
                        title: Text(r.description),
                        subtitle: Text(formatDate(r.date)),
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
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
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
    final buf = StringBuffer('Date,Description,Amount,Balance\n');
    for (final r in rows) {
      buf.writeln([
        formatDate(r.date),
        r.description,
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
  const _SummaryTile({required this.label, required this.amount, required this.currency, this.color});

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
              formatMoney(amount, currency),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color ?? cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
