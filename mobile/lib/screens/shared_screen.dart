// Shared — Splitwise-style sharing between real app users, ACROSS workspaces.
// Port of src/pages/Shared.tsx. A shared item is a cross-user proposal: I record
// my side immediately (I already paid), and the counterparty gets a to-do to
// accept (records a balance-only "I owe you") or reject (raises a conflict I
// resolve). Settlements work the same way. Balances are derived from accepted
// entries + my own pending expense claims. Reading needs `shared.view` (the
// route gate); creating/responding/settling needs `shared.manage`.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/mutations.dart' show Actor, externalAccount;
import '../data/shared_mutations.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/shared_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/common.dart';

class _Partner {
  final String uid;
  final String name;
  final String connectionId;
  const _Partner(this.uid, this.name, this.connectionId);
}

List<_Partner> _partnersOf(List<SharedConnection> connections, String myUid) {
  return connections.map((c) {
    var other = myUid;
    for (final u in c.uids) {
      if (u != myUid) {
        other = u;
        break;
      }
    }
    return _Partner(other, c.names[other] ?? 'Partner', c.id);
  }).toList();
}

SharedMutations _mutations(BuildContext context) {
  final user = context.read<AuthController>().user!;
  return SharedMutations(
    uid: user.uid,
    displayName: user.displayName,
    email: user.email ?? '',
    by: Actor.fromUser(user),
  );
}

/// Look up the local reflection transaction for a shared entry (its id +
/// originating account). The mobile Txn model doesn't parse `sharedEntryId`, so
/// we query the raw doc directly — mirrors the web's transactions.find(...).
Future<({String? id, String? accountId})> _findReflection(String ws, String entryId) async {
  final snap = await FirebaseFirestore.instance
      .collection('transactions')
      .where('workspaceId', isEqualTo: ws)
      .where('sharedEntryId', isEqualTo: entryId)
      .limit(1)
      .get();
  if (snap.docs.isEmpty) return (id: null, accountId: null);
  final d = snap.docs.first;
  final acc = d.data()['accountId'];
  return (id: d.id, accountId: acc is String ? acc : null);
}

class SharedScreen extends StatelessWidget {
  const SharedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shared = context.watch<SharedController>();
    final ws = context.watch<WorkspaceController>();
    final auth = context.watch<AuthController>();
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';
    final canManage = ws.can('shared.manage');
    final myUid = auth.user?.uid ?? '';

    // Read gate: shared.view is required to see balances/partners/history.
    if (!ws.loading && !ws.can('shared.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shared')),
        body: const EmptyView(
          icon: Icons.lock_outline,
          title: 'No access',
          hint: "You don't have permission to view the shared ledger.",
        ),
      );
    }

    if (shared.loading || ws.loading) {
      return Scaffold(appBar: AppBar(title: const Text('Shared')), body: const ListSkeleton());
    }
    if (shared.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shared')),
        body: EmptyView(icon: Icons.error_outline, title: 'Something went wrong', hint: shared.error),
      );
    }

    final partners = _partnersOf(shared.connections, myUid);
    final balances = sharedBalances(myUid, shared.entries);
    final inbox = shared.entries.where((e) => e.pendingForUids.contains(myUid)).toList();
    final conflicts = shared.entries
        .where((e) => e.creatorUid == myUid && e.status == 'rejected' && !e.resolved)
        .toList();
    final pendingInvites = shared.sentInvites.where((i) => i.status == 'pending').toList();

    var owedToMe = 0.0;
    var iOwe = 0.0;
    for (final b in balances) {
      if (b.net > 0) {
        owedToMe += b.net;
      } else {
        iOwe += -b.net;
      }
    }
    final net = owedToMe - iOwe;

    String partnerName(String uid) {
      if (uid == myUid) return 'You';
      for (final p in partners) {
        if (p.uid == uid) return p.name;
      }
      return 'Partner';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared'),
        actions: [
          if (canManage)
            IconButton(
              tooltip: 'Invite a partner',
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: () => _showInvite(context),
            ),
        ],
      ),
      floatingActionButton: (canManage && partners.isNotEmpty)
          ? FloatingActionButton(
              onPressed: () => _showAddExpense(context, partners),
              tooltip: 'Add expense',
              child: const Icon(Icons.add),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        children: [
          // Summary tiles.
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'You are owed',
                  amount: owedToMe,
                  currency: currency,
                  tone: StatTone.success,
                  icon: Icons.south_west,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'You owe',
                  amount: iOwe,
                  currency: currency,
                  tone: StatTone.danger,
                  icon: Icons.north_east,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StatCard(
            label: 'Net balance',
            amount: net,
            currency: currency,
            tone: net > 0.005
                ? StatTone.success
                : net < -0.005
                    ? StatTone.danger
                    : StatTone.neutral,
            icon: Icons.balance,
          ),

          // Inbox — awaiting my response.
          if (canManage && inbox.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'To review',
              trailing: _Pill(text: '${inbox.length}'),
              child: Column(
                children: [
                  for (final e in inbox)
                    _InboxCard(
                      entry: e,
                      currency: currency,
                      payerName: partnerName(e.payerUid),
                    ),
                ],
              ),
            ),
          ],

          // Conflicts — my entries that were rejected.
          if (canManage && conflicts.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'Rejected — needs resolution',
              child: Column(
                children: [
                  for (final e in conflicts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${partnerName(e.counterpartyUid)} rejected ${e.description}'),
                      subtitle: Text(formatMoney(e.amount, currency)),
                      trailing: OutlinedButton(
                        onPressed: () => _showConflict(context, e),
                        child: const Text('Resolve'),
                      ),
                    ),
                ],
              ),
            ),
          ],

          // Partners.
          const SizedBox(height: 12),
          SectionCard(
            title: 'Partners',
            trailing: pendingInvites.isEmpty
                ? null
                : Text(
                    '${pendingInvites.length} pending invite${pendingInvites.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
            child: partners.isEmpty
                ? EmptyView(
                    icon: Icons.groups_outlined,
                    title: 'No partners yet',
                    hint: 'Invite someone by email to start splitting expenses.',
                    action: canManage
                        ? FilledButton(
                            onPressed: () => _showInvite(context),
                            child: const Text('Invite a partner'),
                          )
                        : null,
                  )
                : Column(
                    children: [
                      for (final p in partners)
                        _PartnerTile(
                          partner: p,
                          net: _netFor(balances, p.uid),
                          currency: currency,
                          canSettle: canManage && _netFor(balances, p.uid) < -0.005,
                          onSettle: () => _showSettle(context, p, _netFor(balances, p.uid).abs()),
                        ),
                    ],
                  ),
          ),

          // History.
          const SizedBox(height: 12),
          SectionCard(
            title: 'History',
            child: shared.entries.isEmpty
                ? const EmptyView(icon: Icons.receipt_long_outlined, title: 'Nothing shared yet', hint: 'Add a shared expense to start tracking who owes whom.')
                : Column(
                    children: [
                      for (final e in shared.entries)
                        _HistoryRow(
                          entry: e,
                          currency: currency,
                          myUid: myUid,
                          otherName: partnerName(e.creatorUid == myUid ? e.counterpartyUid : e.creatorUid),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  double _netFor(List<SharedBalance> balances, String uid) {
    for (final b in balances) {
      if (b.uid == uid) return b.net;
    }
    return 0;
  }
}

// ---- summary pill ----------------------------------------------------------

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: TextStyle(color: cs.onPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

// ---- status badge ----------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final SharedEntry entry;
  final String myUid;
  const _StatusBadge({required this.entry, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String label;
    Color bg;
    Color fg;
    if (entry.status == 'accepted') {
      label = 'accepted';
      bg = AppColors.accent2.withValues(alpha: 0.14);
      fg = AppColors.accent2;
    } else if (entry.status == 'rejected') {
      label = 'rejected';
      bg = AppColors.danger.withValues(alpha: 0.14);
      fg = AppColors.danger;
    } else {
      label = entry.creatorUid == myUid ? 'awaiting them' : 'needs your response';
      bg = cs.surfaceContainerHighest;
      fg = cs.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

// ---- partner tile ----------------------------------------------------------

class _PartnerTile extends StatelessWidget {
  final _Partner partner;
  final double net;
  final String currency;
  final bool canSettle;
  final VoidCallback onSettle;
  const _PartnerTile({
    required this.partner,
    required this.net,
    required this.currency,
    required this.canSettle,
    required this.onSettle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settled = net.abs() < 0.005;
    final owesMe = net > 0;
    final sub = settled
        ? 'Settled up'
        : owesMe
            ? 'owes you ${formatMoney(net, currency)}'
            : 'you owe ${formatMoney(-net, currency)}';
    final subColor = settled
        ? cs.onSurfaceVariant
        : owesMe
            ? AppColors.accent2
            : AppColors.danger;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: EntityAvatar(name: partner.name),
      title: Text(partner.name),
      subtitle: Text(sub, style: TextStyle(color: subColor)),
      trailing: canSettle
          ? OutlinedButton(onPressed: onSettle, child: const Text('Settle'))
          : null,
    );
  }
}

// ---- history row -----------------------------------------------------------

class _HistoryRow extends StatelessWidget {
  final SharedEntry entry;
  final String currency;
  final String myUid;
  final String otherName;
  const _HistoryRow({
    required this.entry,
    required this.currency,
    required this.myUid,
    required this.otherName,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iPaid = entry.payerUid == myUid;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          EntityAvatar(name: otherName, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(entry.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (entry.kind == 'settlement') ...[
                      const SizedBox(width: 6),
                      _StatusBadge(entry: entry, myUid: myUid),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text('$otherName · ${formatDate(entry.date)}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${iPaid ? '+' : '−'}${formatMoney(entry.amount, currency)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: iPaid ? AppColors.accent2 : AppColors.danger,
                ),
              ),
              const SizedBox(height: 4),
              if (entry.kind != 'settlement') _StatusBadge(entry: entry, myUid: myUid),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- inbox card ------------------------------------------------------------

class _InboxCard extends StatefulWidget {
  final SharedEntry entry;
  final String currency;
  final String payerName;
  const _InboxCard({required this.entry, required this.currency, required this.payerName});

  @override
  State<_InboxCard> createState() => _InboxCardState();
}

class _InboxCardState extends State<_InboxCard> {
  bool _busy = false;
  String? _accountId;

  bool get _isSettlement => widget.entry.kind == 'settlement';

  @override
  void initState() {
    super.initState();
    final accounts = context.read<DataController>().accounts;
    _accountId = accounts.isNotEmpty ? accounts.first.id : null;
  }

  Future<void> _run(Future<void> Function() fn, String okMsg) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMsg)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _accept() async {
    final wsC = context.read<WorkspaceController>();
    final ws = wsC.activeWorkspaceId;
    final fy = wsC.activeWorkspace?.fyStartMonth ?? 4;
    final data = context.read<DataController>();
    if (ws == null) return;
    final sm = _mutations(context);
    final entry = widget.entry;
    if (_isSettlement) {
      await sm.acceptSettlement(
        entry: entry,
        workspaceId: ws,
        fyStartMonth: fy,
        contacts: data.contacts,
        debts: data.debts,
        accountId: _accountId,
      );
    } else {
      await sm.acceptSharedExpense(
        entry: entry,
        workspaceId: ws,
        fyStartMonth: fy,
        contacts: data.contacts,
        debts: data.debts,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accounts = context.watch<DataController>().accounts;
    final e = widget.entry;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.description, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            '${_isSettlement ? '${widget.payerName} paid you' : '${widget.payerName} paid'} · ${formatMoney(e.amount, widget.currency)}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          if (_isSettlement) ...[
            DropdownButtonFormField<String>(
              value: _accountId,
              decoration: const InputDecoration(labelText: 'Into account', isDense: true),
              items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
              onChanged: _busy ? null : (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || (_isSettlement && _accountId == null)
                      ? null
                      : () => _run(_accept, 'Accepted'),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Accept'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _busy ? null : () => _run(() => _mutations(context).rejectSharedEntry(e), 'Rejected'),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- invite dialog ---------------------------------------------------------

void _showInvite(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: const _InviteSheet(),
    ),
  );
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet();
  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _valid => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  Future<void> _save() async {
    if (!_valid) return;
    setState(() => _busy = true);
    try {
      await _mutations(context).inviteSharedPartner(_email.text.trim());
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite sent')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invite a partner', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            "They'll be able to share expenses with you once they sign in. They cannot see or enter your workspace.",
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email', hintText: 'friend@example.com'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy || !_valid ? null : _save,
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send invite'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- add expense dialog ----------------------------------------------------

void _showAddExpense(BuildContext context, List<_Partner> partners) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _AddExpenseSheet(partners: partners),
    ),
  );
}

class _AddExpenseSheet extends StatefulWidget {
  final List<_Partner> partners;
  const _AddExpenseSheet({required this.partners});
  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  DateTime _date = DateTime.now();
  String? _accountId;
  String? _categoryId;
  bool _includeMe = true;
  late Set<String> _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final data = context.read<DataController>();
    _accountId = data.accounts.isNotEmpty ? data.accounts.first.id : null;
    final expenseCats = data.categories.where((c) => c.kind == 'expense').toList();
    _categoryId = expenseCats.isNotEmpty ? expenseCats.first.id : null;
    _selected = {for (final p in widget.partners) p.uid};
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  double get _total => double.tryParse(_amount.text.trim()) ?? 0;
  List<_Partner> get _chosen => widget.partners.where((p) => _selected.contains(p.uid)).toList();
  int get _splitCount => _chosen.length + (_includeMe ? 1 : 0);
  double get _perHead => _splitCount > 0 ? roundMoney(_total / _splitCount) : 0.0;
  bool get _valid =>
      _description.text.trim().isNotEmpty && _total > 0 && _accountId != null && _chosen.isNotEmpty;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_valid) return;
    final wsC = context.read<WorkspaceController>();
    final ws = wsC.activeWorkspaceId;
    final fy = wsC.activeWorkspace?.fyStartMonth ?? 4;
    final data = context.read<DataController>();
    if (ws == null) return;

    // Equal split; the payer (me) absorbs any rounding remainder.
    final base = _perHead;
    final participants = _chosen
        .map((p) => SharedExpenseParticipant(
              counterpartyUid: p.uid,
              counterpartyName: p.name,
              connectionId: p.connectionId,
              share: base,
            ))
        .toList();
    final othersTotal = roundMoney(base * _chosen.length);
    final myShareRaw = _includeMe ? roundMoney(_total - othersTotal) : 0.0;
    final myShare = myShareRaw > 0 ? myShareRaw : 0.0;

    setState(() => _busy = true);
    try {
      await _mutations(context).createSharedExpense(
        workspaceId: ws,
        fyStartMonth: fy,
        accountId: _accountId!,
        description: _description.text.trim(),
        date: _date,
        myShare: myShare,
        myCategoryId: _includeMe ? _categoryId : null,
        participants: participants,
        contacts: data.contacts,
        debts: data.debts,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Shared expense recorded')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataController>();
    final cs = Theme.of(context).colorScheme;
    final currency = context.read<WorkspaceController>().activeWorkspace?.baseCurrency ?? 'INR';
    final accounts = data.accounts;
    final expenseCats = data.categories.where((c) => c.kind == 'expense').toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add shared expense', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description', hintText: 'Dinner, groceries…'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Total amount', prefixText: '₹ '),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date'),
                      child: Text(formatDate(_date)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _accountId,
              decoration: const InputDecoration(labelText: 'Paid from'),
              items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Split equally between',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                if (_splitCount > 0 && _total > 0)
                  Text('${formatMoney(_perHead, currency)} each',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _includeMe,
              title: const Text('You'),
              onChanged: (v) => setState(() => _includeMe = v ?? false),
            ),
            for (final p in widget.partners)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _selected.contains(p.uid),
                title: Text(p.name),
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _selected.add(p.uid);
                  } else {
                    _selected.remove(p.uid);
                  }
                }),
              ),
            if (_includeMe) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _categoryId,
                decoration: const InputDecoration(labelText: 'My share category'),
                items: [
                  for (final c in expenseCats) DropdownMenuItem(value: c.id, child: Text(c.name))
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy || !_valid ? null : _save,
                child: _busy
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Record & request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- settle dialog ---------------------------------------------------------

void _showSettle(BuildContext context, _Partner partner, double suggested) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _SettleSheet(partner: partner, suggested: suggested),
    ),
  );
}

class _SettleSheet extends StatefulWidget {
  final _Partner partner;
  final double suggested;
  const _SettleSheet({required this.partner, required this.suggested});
  @override
  State<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends State<_SettleSheet> {
  late final TextEditingController _amount;
  String? _accountId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.suggested.toString());
    final accounts = context.read<DataController>().accounts;
    _accountId = accounts.isNotEmpty ? accounts.first.id : null;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  bool get _valid => (double.tryParse(_amount.text.trim()) ?? 0) > 0 && _accountId != null;

  Future<void> _save() async {
    if (!_valid) return;
    final wsC = context.read<WorkspaceController>();
    final ws = wsC.activeWorkspaceId;
    final fy = wsC.activeWorkspace?.fyStartMonth ?? 4;
    final data = context.read<DataController>();
    if (ws == null) return;
    final amount = roundMoney(double.tryParse(_amount.text.trim()) ?? 0);
    setState(() => _busy = true);
    try {
      await _mutations(context).proposeSettlement(
        counterpartyUid: widget.partner.uid,
        counterpartyName: widget.partner.name,
        connectionId: widget.partner.connectionId,
        amount: amount,
        description: 'Settlement to ${widget.partner.name}',
        date: DateTime.now(),
        workspaceId: ws,
        fyStartMonth: fy,
        accountId: _accountId!,
        contacts: data.contacts,
        debts: data.debts,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Settlement proposed')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currency = context.read<WorkspaceController>().activeWorkspace?.baseCurrency ?? 'INR';
    final accounts = context.watch<DataController>().accounts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settle up with ${widget.partner.name}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Records the payment from your account now; ${widget.partner.name} must accept it to record their side.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Amount ($currency)', prefixText: '₹ '),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _accountId,
            decoration: const InputDecoration(labelText: 'Paid from'),
            items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy || !_valid ? null : _save,
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Propose settlement'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- conflict dialog -------------------------------------------------------

void _showConflict(BuildContext context, SharedEntry entry) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ConflictSheet(entry: entry),
    ),
  );
}

class _ConflictSheet extends StatefulWidget {
  final SharedEntry entry;
  const _ConflictSheet({required this.entry});
  @override
  State<_ConflictSheet> createState() => _ConflictSheetState();
}

class _ConflictSheetState extends State<_ConflictSheet> {
  String? _categoryId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final expenseCats = context.read<DataController>().categories.where((c) => c.kind == 'expense').toList();
    _categoryId = expenseCats.isNotEmpty ? expenseCats.first.id : null;
  }

  Future<void> _run(Future<void> Function() fn, String okMsg) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMsg)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _resolve(String mode) async {
    final wsC = context.read<WorkspaceController>();
    final ws = wsC.activeWorkspaceId;
    final fy = wsC.activeWorkspace?.fyStartMonth ?? 4;
    final data = context.read<DataController>();
    if (ws == null) return;
    final refl = await _findReflection(ws, widget.entry.id);
    final acct = (refl.accountId != null && refl.accountId != externalAccount)
        ? refl.accountId!
        : (data.accounts.isNotEmpty ? data.accounts.first.id : '');
    if (!mounted) return;
    await _mutations(context).resolveConflict(
      entry: widget.entry,
      mode: mode,
      reflectionTxnId: refl.id ?? '',
      myCategoryId: _categoryId,
      fyStartMonth: fy,
      date: widget.entry.date,
      accountId: acct,
      workspaceId: ws,
    );
  }

  Future<void> _rebill() async {
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    if (ws == null) return;
    final refl = await _findReflection(ws, widget.entry.id);
    if (!mounted) return;
    await _mutations(context).rebillSharedEntry(entry: widget.entry, reflectionTxnId: refl.id);
  }

  Future<void> _withdraw() async {
    final ws = context.read<WorkspaceController>().activeWorkspaceId;
    if (ws == null) return;
    final refl = await _findReflection(ws, widget.entry.id);
    if (!mounted) return;
    await _mutations(context).withdrawSharedEntry(widget.entry, refl.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final expenseCats = context.watch<DataController>().categories.where((c) => c.kind == 'expense').toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resolve rejected share', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${widget.entry.description} was rejected. Choose how to reconcile your books — you already paid this amount.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _categoryId,
              decoration: const InputDecoration(labelText: 'Absorb under category'),
              items: [for (final c in expenseCats) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : () => _run(_rebill, 'Re-sent for approval'),
                child: const Text('Re-send for approval'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : () => _run(() => _resolve('absorb'), 'Conflict resolved'),
                child: const Text('Absorb as my expense'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : () => _run(() => _resolve('remove'), 'Conflict resolved'),
                child: const Text("Remove the claim (it wasn't my cost)"),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _busy ? null : () => _run(_withdraw, 'Withdrawn'),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Withdraw entry entirely'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
