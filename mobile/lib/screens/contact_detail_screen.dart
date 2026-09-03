import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../data/settle_up.dart';
import '../services/khata_pdf.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';
import 'transaction_detail.dart';

const _purposeLabels = <String, String>{
  'loan': 'Loans',
  'custodial_savings': 'Custodial savings',
  'lending': 'Lendings',
  'reimbursable': 'Reimbursable',
  'informal': 'Informal',
  'shared': 'Shared',
};

class ContactDetailScreen extends StatelessWidget {
  final String contactId;
  const ContactDetailScreen({super.key, required this.contactId});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final ws = context.watch<WorkspaceController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';

    final contact = data.contactsById[contactId];
    if (contact == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contact')),
        body: const EmptyView(title: 'Contact not found'),
      );
    }

    final position = data.positionOf(contactId);

    final contactTxns = data.transactions.where((t) => t.contactId == contactId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final contactDebts = data.debts.where((d) => d.contactId == contactId).toList();

    final netTone = position.net > 0.005
        ? StatTone.success
        : (position.net < -0.005 ? StatTone.danger : StatTone.neutral);

    final canViewTxns = ws.can('transactions.view');

    // Emails render with their label (e.g. "Personal: a@b.com"); fall back to
    // the legacy single email when no array is present.
    final emailBits = contact.emails.isNotEmpty
        ? contact.emails.map((e) => '${e.label}: ${e.value}').toList()
        : (contact.email != null && contact.email!.isNotEmpty ? [contact.email!] : <String>[]);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(contact.name),
          actions: [
            IconButton(
              tooltip: 'Share ledger',
              icon: const Icon(Icons.ios_share),
              onPressed: () => _shareKhata(context, contact),
            ),
            if (canViewTxns)
              IconButton(
                tooltip: 'Open in Transactions',
                icon: const Icon(Icons.swap_horiz),
                onPressed: () => context.push('/txns?contact=$contactId'),
              ),
          ],
        ),
        body: Column(
          children: [
            // Hero: avatar + name + type/relationship badges.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  EntityAvatar(name: contact.name, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(contact.name,
                            style: Theme.of(context).textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _Badge(contact.type == 'business' ? 'Business' : 'Person'),
                            if (contact.relationship == 'family') _Badge('Family'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Contact info — one icon-led row per detail, not a cramped run-on line.
            if (contact.phone != null && contact.phone!.isNotEmpty ||
                emailBits.isNotEmpty ||
                (contact.address != null && contact.address!.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (contact.phone != null && contact.phone!.isNotEmpty)
                      _infoRow(context, Icons.phone_outlined, contact.phone!),
                    for (final e in contact.emails)
                      _infoRow(context, Icons.mail_outline, e.value, tag: e.label),
                    if (contact.emails.isEmpty && contact.email != null && contact.email!.isNotEmpty)
                      _infoRow(context, Icons.mail_outline, contact.email!),
                    if (contact.address != null && contact.address!.isNotEmpty)
                      _infoRow(context, Icons.location_on_outlined, contact.address!),
                  ],
                ),
              ),
            // Position summary — compact, unified card instead of three tiles.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: _positionCard(context, position, currency, netTone),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Transactions'),
                Tab(text: 'Debts'),
                Tab(text: 'Report'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _transactionsTab(context, data, contactTxns, currency),
                  _debtsTab(context, data, contactDebts, currency),
                  _reportTab(context, position, contactTxns.length, contactDebts, currency),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text, {String? tag}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: text),
                  if (tag != null)
                    TextSpan(
                      text: '  $tag',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
              style: TextStyle(fontSize: 13.5, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _positionCard(BuildContext context, ContactPosition position, String currency, StatTone netTone) {
    final cs = Theme.of(context).colorScheme;
    Color toneColor(StatTone t) => switch (t) {
          StatTone.success => AppColors.accent2,
          StatTone.danger => AppColors.danger,
          StatTone.neutral => cs.onSurface,
        };
    Widget cell(String label, double amount, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatMoneyCompact(amount, currency),
                  maxLines: 1,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
        );
    Widget divider() => Container(
          width: 1,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: cs.outlineVariant.withValues(alpha: 0.6),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            Row(
              children: [
                cell('Net', position.net, toneColor(netTone)),
                divider(),
                cell('In', position.totalIn, AppColors.accent2),
                divider(),
                cell('Out', position.totalOut, AppColors.danger),
              ],
            ),
            Builder(builder: (context) {
              final data = context.watch<DataController>();
              final ws = context.watch<WorkspaceController>();
              if (!ws.can('transactions.create')) return const SizedBox.shrink();
              final plan = buildSettleUpPlan(contactId, data.debts, data.transactions, lineIdSeed: 0);
              if (plan.isEmpty || plan.signedTotal.abs() <= 0.005) {
                return const SizedBox.shrink();
              }
              final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.handshake_outlined, size: 18),
                    label: Text(plan.signedTotal > 0
                        ? 'Settle up: collect ${formatMoney(plan.signedTotal, currency)}'
                        : 'Settle up: pay ${formatMoney(plan.signedTotal.abs(), currency)}'),
                    onPressed: () => _confirmSettleUp(context, plan),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// One transaction that closes every open debt with this contact (repayment
  /// lines for each), previewed before posting.
  Future<void> _confirmSettleUp(BuildContext context, SettleUpPlan stale) async {
    final data = context.read<DataController>();
    final wsC = context.read<WorkspaceController>();
    final wsId = wsC.activeWorkspaceId;
    final fyStart = wsC.activeWorkspace?.fyStartMonth ?? 4;
    final currency = wsC.activeWorkspace?.baseCurrency ?? 'INR';
    final user = context.read<AuthController>().user;
    if (wsId == null || user == null) return;
    // Rebuild fresh (data may have moved since the button rendered).
    final seed = DateTime.now().microsecondsSinceEpoch;
    final plan = buildSettleUpPlan(contactId, data.debts, data.transactions, lineIdSeed: seed);
    if (plan.isEmpty) return;
    final accounts = data.accounts;
    if (accounts.isEmpty) return;
    String? accountId = accounts.first.id;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Settle up debts?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('One transaction will close ${plan.debts.length} open '
                  'debt${plan.debts.length == 1 ? '' : 's'}:'),
              const SizedBox(height: 8),
              for (final d in plan.debts)
                Text(
                  '- ${d.label?.isNotEmpty == true ? d.label : _purposeLabels[d.purpose] ?? d.purpose}'
                  ' (${d.direction == 'owed' ? 'receivable' : 'payable'})',
                  style: const TextStyle(fontSize: 13),
                ),
              const SizedBox(height: 10),
              Text(
                plan.signedTotal > 0
                    ? 'Net: you collect ${formatMoney(plan.signedTotal, currency)}'
                    : 'Net: you pay ${formatMoney(plan.signedTotal.abs(), currency)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: accountId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Account', isDense: true),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setDlg(() => accountId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Post settle-up')),
          ],
        ),
      ),
    );
    if (ok != true || accountId == null || !context.mounted) return;
    try {
      final now = DateTime.now();
      final contactName = data.contactsById[contactId]?.name ?? '';
      await Mutations(Actor.fromUser(user)).createTransaction(
        wsId,
        date: now,
        note: 'Settle-up with $contactName',
        accountId: accountId!,
        contactId: contactId,
        totalAmount: plan.signedTotal,
        financialYear: financialYearOf(now, fyStart),
        lines: plan.lines,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settle-up recorded')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Widget _transactionsTab(BuildContext context, DataController data, List<Txn> txns, String currency) {
    if (txns.isEmpty) {
      return const EmptyView(title: 'No transactions with this contact');
    }
    // Chat-style: oldest -> newest, with a date separator between different days.
    final ordered = [...txns]..sort((a, b) => a.date.compareTo(b.date));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: ordered.length,
      itemBuilder: (context, i) {
        final t = ordered[i];
        final day = formatDate(t.date);
        final showSep = i == 0 || formatDate(ordered[i - 1].date) != day;
        // Money received (>= 0) reads as incoming -> left; paid out -> right.
        final incoming = t.totalAmount >= 0;
        final debtLabels = t.lines
            .where((l) => l.debtId != null)
            .map((l) => data.debtsById[l.debtId]?.label)
            .whereType<String>()
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSep) _dateSeparator(context, day),
            Align(
              alignment: incoming ? Alignment.centerLeft : Alignment.centerRight,
              child: _txnBubble(context, t, currency, incoming, debtLabels),
            ),
          ],
        );
      },
    );
  }

  Widget _dateSeparator(BuildContext context, String day) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            day,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _txnBubble(BuildContext context, Txn t, String currency, bool incoming, List<String> debtLabels) {
    final cs = Theme.of(context).colorScheme;
    final amountColor = incoming ? AppColors.accent2 : AppColors.danger;
    final sign = incoming ? '+' : '−';
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      child: Material(
        color: incoming ? cs.surfaceContainerHigh : cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(incoming ? 4 : 16),
          topRight: Radius.circular(incoming ? 16 : 4),
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(16),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showTransactionDetail(context, t),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$sign${formatMoney(t.totalAmount.abs(), currency)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: amountColor,
                  ),
                ),
                if (t.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(t.note!, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ],
                if (t.lines.isNotEmpty || debtLabels.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final l in t.lines.take(3)) _MiniBadge(_lineTypeLabel(l.type)),
                      for (final label in debtLabels) _MiniBadge(label, color: AppColors.accent2),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _debtsTab(BuildContext context, DataController data, List<Debt> debts, String currency) {
    if (debts.isEmpty) {
      return const EmptyView(title: 'No debts with this contact');
    }
    // Group the contact's debts by purpose, preserving first-seen order.
    final byPurpose = <String, List<Debt>>{};
    for (final d in debts) {
      byPurpose.putIfAbsent(d.purpose, () => []).add(d);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        for (final entry in byPurpose.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              _purposeLabels[entry.key] ?? entry.key,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          for (final d in entry.value)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.label ?? _purposeLabels[d.purpose] ?? 'Debt',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _Badge(
                              d.direction == 'owed' ? 'Receivable' : 'Payable',
                              color: d.direction == 'owed' ? AppColors.accent2 : AppColors.danger,
                            ),
                            _Badge(d.status),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatMoney(data.outstandingOf(d.id), currency),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _reportTab(
    BuildContext context,
    ContactPosition position,
    int txnCount,
    List<Debt> debts,
    String currency,
  ) {
    final openDebts = debts.where((d) => d.status == 'open').length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DetailRow('Transactions', '$txnCount'),
                DetailRow('Total received', formatMoney(position.totalIn, currency)),
                DetailRow('Total paid', formatMoney(position.totalOut, currency)),
                DetailRow('Open debts', '$openDebts'),
                DetailRow('Net position', formatMoney(position.net, currency)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- shareable khata -----------------------------------------------------

  /// Everything the ledger artifacts need, computed once from live data.
  ({
    double net,
    List<KhataEntry> entries,
    List<KhataDueLine> openDues,
    String currency,
    String workspaceName,
  }) _khataData(BuildContext context, Contact contact) {
    final data = context.read<DataController>();
    final ws = context.read<WorkspaceController>();
    final position = data.positionOf(contact.id);

    // The ledger must reconcile with the net position banner, which is the
    // DEBT position (borrow/lend/repayment on this contact's debts). So each
    // entry carries its position delta, and the entry set covers every
    // transaction that either is tagged to the contact or touches one of
    // their debts (a repayment can live on an untagged transaction).
    final contactDebts = {
      for (final d in data.debts.where((d) => d.contactId == contact.id)) d.id: d,
    };
    double positionDeltaOf(Txn t) {
      var v = 0.0;
      for (final l in t.lines) {
        final debt = contactDebts[l.debtId];
        if (debt == null) continue;
        final establishing = debt.direction == 'owe' ? 'borrow' : 'lend';
        final sign = debt.direction == 'owed' ? 1 : -1;
        if (l.type == establishing) {
          v += sign * l.amount;
        } else if (l.type == 'repayment') {
          v -= sign * l.amount;
        }
      }
      return v;
    }

    final entries = <KhataEntry>[];
    for (final t in data.transactions) {
      final delta = positionDeltaOf(t);
      if (t.contactId != contact.id && delta.abs() < 0.005) continue;
      entries.add(KhataEntry(
        t.date,
        t.note?.isNotEmpty == true ? t.note! : 'Transaction',
        t.totalAmount,
        positionDelta: roundMoney(delta),
      ));
    }
    entries.sort((a, b) => b.date.compareTo(a.date));
    final openDues = [
      for (final d in data.dues
          .where((d) => d.contactId == contact.id && (d.status == 'open' || d.status == 'partial')))
        KhataDueLine(d.title, d.dueDate, roundMoney(d.amount - data.settledOf(d.id)), d.direction),
    ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return (
      net: position.net,
      entries: entries,
      openDues: openDues,
      currency: ws.activeWorkspace?.baseCurrency ?? 'INR',
      workspaceName: ws.activeWorkspace?.name ?? 'NizKhata',
    );
  }

  /// App logo bytes for PDF branding; a missing asset never blocks a share.
  static Future<Uint8List?> _appLogoBytes() async {
    try {
      final data = await rootBundle.load('assets/icon.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  void _shareKhata(BuildContext context, Contact contact) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Share ledger as PDF'),
              subtitle: const Text('Net position, outstanding dues and full history'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final k = _khataData(context, contact);
                final logo = await _appLogoBytes();
                final bytes = buildKhataPdf(
                  workspaceName: k.workspaceName,
                  contactName: contact.name,
                  net: k.net,
                  entries: k.entries,
                  openDues: k.openDues,
                  currency: k.currency,
                  logoPng: logo,
                );
                final dir = await getTemporaryDirectory();
                final safe = contact.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').toLowerCase();
                final file = File('${dir.path}/ledger-$safe.pdf');
                await file.writeAsBytes(bytes);
                await Share.shareXFiles(
                  [XFile(file.path, name: 'ledger-$safe.pdf', mimeType: 'application/pdf')],
                  text: 'Ledger — ${contact.name}',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Share summary as text'),
              subtitle: const Text('Short WhatsApp-ready standing + recent entries'),
              onTap: () {
                Navigator.pop(sheetCtx);
                final k = _khataData(context, contact);
                Share.share(buildKhataText(
                  contactName: contact.name,
                  net: k.net,
                  entries: k.entries,
                  openDues: k.openDues,
                  currency: k.currency,
                ));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

const _lineTypeLabels = <String, String>{
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
  'tax': 'Tax',
};

String _lineTypeLabel(String type) => _lineTypeLabels[type] ?? type;

/// Compact pill used inside chat bubbles for line types / debt labels.
class _MiniBadge extends StatelessWidget {
  final String text;
  final Color? color;
  const _MiniBadge(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = color ?? cs.outlineVariant;
    final fg = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: base.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color? color;
  const _Badge(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? cs.outlineVariant).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: (color ?? cs.outlineVariant).withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
