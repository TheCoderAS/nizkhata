import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/due_settlement.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../services/import_learning.dart';
import '../services/password_store.dart';
import '../services/statement_parser.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';

/// Statement import — upload → analyse (password prompt for encrypted files) →
/// map columns → review rows in a table with checkboxes and per-row edits →
/// import. All parsing happens on-device; a remembered password is kept only
/// in the device's encrypted keystore and never leaves the device.
class ImportScreen extends StatefulWidget {
  final String? initialAccountId;
  const ImportScreen({super.key, this.initialAccountId});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

enum _Step { pick, mapping, review, importing, done }

/// What counts as "already imported" when flagging duplicates.
enum _DupMode { strict, dateAmount, off }

/// A parsed statement row plus the review screen's state for it.
class _ReviewRow {
  final ImportRowDraft draft;
  bool selected;
  bool duplicate;
  String? categoryId; // per-row override; falls back to the defaults
  bool categorySuggested = false; // categoryId came from learned history
  String? matchedDueId; // open due this row appears to settle
  bool linkDue = false; // import as a settlement of matchedDueId
  _ReviewRow(this.draft, {required this.selected, required this.duplicate});
}

class _ImportScreenState extends State<ImportScreen> {
  _Step _step = _Step.pick;
  String? _accountId;
  bool _busy = false;

  // Parsed file.
  String _fileName = '';
  StatementGrid? _grid;
  ColumnMapping _mapping = ColumnMapping();
  DateOrder _dateOrder = DateOrder.dmy;
  bool _rememberPassword = true;
  bool _profileApplied = false; // saved mapping profile matched this file

  // Review state.
  List<_ReviewRow> _rows = [];
  String? _defaultExpenseCat;
  String? _defaultIncomeCat;
  _DupMode _dupMode = _DupMode.strict;
  Set<String> _existingStrict = {};
  Set<String> _existingDateAmount = {};

  // Import progress.
  int _importDone = 0;
  int _importTotal = 0;
  int _imported = 0;
  int _settled = 0; // rows imported as due settlements

  static final _dateFmt = DateFormat('dd MMM yy');

  @override
  void initState() {
    super.initState();
    _accountId = widget.initialAccountId;
  }

  // ---- step 1: pick + analyse ---------------------------------------------

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'tsv', 'txt', 'xls', 'xlsx', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _toast("Couldn't read the selected file.");
      return;
    }
    await _analyze(bytes, file.name);
  }

  /// Analyse the file. If it's password-protected, first silently try any
  /// password remembered for this account; only prompt if that's missing or
  /// wrong. [triedRemembered] guards against re-trying the stored password.
  Future<void> _analyze(Uint8List bytes, String name,
      {String? password, bool triedRemembered = false}) async {
    setState(() => _busy = true);
    try {
      // Let the spinner paint before the (synchronous) parse work.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final grid = parseStatement(bytes, name, password: password);
      var mapping = suggestMapping(grid.header);
      var order = DateOrder.dmy;
      if (mapping.date != null) {
        order = detectDateOrder(
            grid.dataRows.take(50).map((r) => mapping.date! < r.length ? r[mapping.date!] : ''));
      }
      // A bank's statement format rarely changes: if a saved mapping profile
      // matches this file's header layout, apply it wholesale so month two
      // is one tap. A changed layout falls back to the fresh suggestion.
      _profileApplied = false;
      final profile = await _loadProfile();
      if (profile != null && profile['header'] == _headerKey(grid.header)) {
        int? col(String k) => (profile[k] as num?)?.toInt();
        mapping = ColumnMapping(
          date: col('date'),
          description: col('desc'),
          amount: col('amount'),
          debit: col('debit'),
          credit: col('credit'),
          reference: col('ref'),
          balance: col('balance'),
        );
        final oi = (profile['order'] as num?)?.toInt() ?? 0;
        if (oi >= 0 && oi < DateOrder.values.length) order = DateOrder.values[oi];
        final di = (profile['dup'] as num?)?.toInt() ?? 0;
        if (di >= 0 && di < _DupMode.values.length) _dupMode = _DupMode.values[di];
        _defaultExpenseCat = profile['expCat'] as String?;
        _defaultIncomeCat = profile['incCat'] as String?;
        _profileApplied = true;
      }
      // A password that worked is saved for this account when "remember" is on,
      // or any previously-saved one cleared when the user turned it off.
      if (password != null && password.isNotEmpty && _accountId != null) {
        if (_rememberPassword) {
          await PasswordStore.instance.set(_accountId!, password);
        } else {
          await PasswordStore.instance.remove(_accountId!);
        }
      }
      setState(() {
        _fileName = name;
        _grid = grid;
        _mapping = mapping;
        _dateOrder = order;
        _step = _Step.mapping;
        _busy = false;
      });
    } on StatementPasswordRequired catch (e) {
      // Try a remembered password once before bothering the user.
      if (!triedRemembered && !e.wrongPassword && _accountId != null) {
        final saved = await PasswordStore.instance.get(_accountId!);
        if (saved != null && saved.isNotEmpty && mounted) {
          await _analyze(bytes, name, password: saved, triedRemembered: true);
          return;
        }
      }
      setState(() => _busy = false);
      final initial = _accountId != null ? await PasswordStore.instance.get(_accountId!) : null;
      if (!mounted) return;
      final pw = await _askPassword(wrongPassword: e.wrongPassword, initial: initial ?? '');
      if (pw != null && mounted) {
        await _analyze(bytes, name, password: pw, triedRemembered: true);
      }
    } on StatementUnsupported catch (e) {
      setState(() => _busy = false);
      _showError(e.message);
    } catch (e) {
      setState(() => _busy = false);
      _showError("Couldn't analyse this file: $e");
    }
  }

  Future<String?> _askPassword({required bool wrongPassword, String initial = ''}) {
    final controller = TextEditingController(text: initial);
    var obscure = true;
    return showDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Password required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(wrongPassword
                  ? 'That password didn\'t work. Try again.'
                  : 'This document is password-protected. Enter its password to open it.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setDlg(() => obscure = !obscure),
                  ),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _rememberPassword,
                onChanged: (v) => setDlg(() => setState(() => _rememberPassword = v ?? true)),
                title: const Text('Remember for this account'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
              Text(
                'Kept encrypted on this device only — never uploaded.',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text("Can't import this file"),
        content: Text(message),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---- mapping profile (per account, local) --------------------------------

  String _headerKey(List<String> header) =>
      header.map((h) => h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')).join('|');

  Future<Map<String, dynamic>?> _loadProfile() async {
    final accountId = _accountId;
    if (accountId == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('import_profile_$accountId');
      if (raw == null) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveProfile() async {
    final accountId = _accountId;
    final grid = _grid;
    if (accountId == null || grid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'import_profile_$accountId',
          jsonEncode({
            'header': _headerKey(grid.header),
            'date': _mapping.date,
            'desc': _mapping.description,
            'amount': _mapping.amount,
            'debit': _mapping.debit,
            'credit': _mapping.credit,
            'ref': _mapping.reference,
            'balance': _mapping.balance,
            'order': _dateOrder.index,
            'dup': _dupMode.index,
            'expCat': _defaultExpenseCat,
            'incCat': _defaultIncomeCat,
          }));
    } catch (_) {
      // Best-effort convenience — never block an import on prefs.
    }
  }

  // ---- step 2 → 3: build review rows --------------------------------------

  void _buildReview() {
    final grid = _grid;
    final accountId = _accountId;
    if (grid == null || accountId == null || !_mapping.complete) return;
    final data = context.read<DataController>();

    final drafts = buildImportRows(grid, _mapping, _dateOrder);
    // Identity of everything already in this account: stored importKeys plus
    // recomputed fingerprints, so both prior imports and manual entries match.
    // Two sets, one per matching strictness the user can pick.
    final strict = <String>{};
    final dateAmount = <String>{};
    for (final t in data.transactions) {
      if (t.accountId != accountId) continue;
      if (t.importKey != null && t.importKey!.isNotEmpty) strict.add(t.importKey!);
      strict.add(importFingerprint(
        accountId: accountId,
        date: t.date,
        amount: t.totalAmount,
        refOrDesc: t.note ?? '',
      ));
      dateAmount.add(importFingerprint(
        accountId: accountId,
        date: t.date,
        amount: t.totalAmount,
        refOrDesc: '',
      ));
    }

    final rows = [for (final d in drafts) _ReviewRow(d, selected: false, duplicate: false)];

    // Learned categories: the user's own categorized history is the training
    // data — suggest a category for each row by narration-token overlap.
    final memory = CategoryMemory.fromTransactions(data.transactions);
    if (!memory.isEmpty) {
      final catsById = {for (final c in data.categories) c.id: c};
      for (final r in rows) {
        if (!r.draft.parseable) continue;
        final suggestion = memory.suggest(
            r.draft.description.isNotEmpty ? r.draft.description : r.draft.reference);
        if (suggestion == null) continue;
        // Only apply when the category's kind matches the row's direction.
        final kind = catsById[suggestion]?.kind;
        final wantKind = r.draft.amount! < 0 ? 'expense' : 'income';
        if (kind == wantKind) {
          r.categoryId = suggestion;
          r.categorySuggested = true;
        }
      }
    }

    // Due matching: a row whose sign matches an open due's direction and whose
    // magnitude equals that due's remaining amount (to the paise) very likely
    // IS its settlement. Each due links to at most one row.
    final usedDues = <String>{};
    final candidates = data.dues
        .where((d) => d.status == 'open' || d.status == 'partial')
        .toList();
    final byDate = [...rows.where((r) => r.draft.parseable)]
      ..sort((a, b) => a.draft.date!.compareTo(b.draft.date!));
    for (final r in byDate) {
      final amount = r.draft.amount!;
      Due? best;
      Duration? bestGap;
      for (final due in candidates) {
        if (usedDues.contains(due.id)) continue;
        final remaining = due.amount - data.settledOf(due.id);
        if (remaining <= 0.005) continue;
        final signOk = due.direction == 'payable' ? amount < 0 : amount > 0;
        if (!signOk) continue;
        if ((amount.abs() - remaining).abs() > 0.01) continue;
        final gap = (r.draft.date!.difference(due.dueDate)).abs();
        if (gap > const Duration(days: 92)) continue;
        if (bestGap == null || gap < bestGap) {
          best = due;
          bestGap = gap;
        }
      }
      if (best != null) {
        usedDues.add(best.id);
        r.matchedDueId = best.id;
        r.linkDue = true;
      }
    }

    setState(() {
      _existingStrict = strict;
      _existingDateAmount = dateAmount;
      _rows = rows;
      _applyDupMode();
      _step = _Step.review;
    });
  }

  /// Recompute every row's duplicate flag (and default selection) for the
  /// current matching mode. Unreadable rows stay unselected until fixed.
  void _applyDupMode() {
    for (final r in _rows) {
      if (!r.draft.parseable) {
        r.duplicate = false;
        r.selected = false;
        continue;
      }
      r.duplicate = _isDuplicate(r.draft);
      r.selected = !r.duplicate;
    }
  }

  bool _isDuplicate(ImportRowDraft d) {
    final accountId = _accountId;
    if (accountId == null || !d.parseable) return false;
    switch (_dupMode) {
      case _DupMode.off:
        return false;
      case _DupMode.strict:
        return _existingStrict.contains(_fingerprintOf(d, accountId));
      case _DupMode.dateAmount:
        return _existingDateAmount.contains(importFingerprint(
            accountId: accountId, date: d.date!, amount: d.amount!, refOrDesc: ''));
    }
  }

  String _fingerprintOf(ImportRowDraft d, String accountId) => importFingerprint(
        accountId: accountId,
        date: d.date!,
        amount: d.amount!,
        refOrDesc: d.reference.isNotEmpty ? d.reference : d.description,
      );

  // ---- step 4: import ------------------------------------------------------

  Future<void> _import() async {
    final accountId = _accountId;
    final wsC = context.read<WorkspaceController>();
    final ws = wsC.activeWorkspaceId;
    final fyStart = wsC.activeWorkspace?.fyStartMonth ?? 4;
    final user = context.read<AuthController>().user;
    if (accountId == null || ws == null || user == null) return;

    final picked = _rows.where((r) => r.selected).toList();
    if (picked.isEmpty) return;
    final data = context.read<DataController>();

    final settleRows =
        picked.where((r) => r.linkDue && r.matchedDueId != null).toList();
    final plainRows = picked.where((r) => !(r.linkDue && r.matchedDueId != null)).toList();

    final records = <Map<String, dynamic>>[
      for (final r in plainRows)
        {
          'date': r.draft.date!,
          'amount': r.draft.amount!,
          'note': _noteOf(r.draft),
          'categoryId': r.categoryId ??
              (r.draft.amount! < 0 ? _defaultExpenseCat : _defaultIncomeCat),
          'importKey': _fingerprintOf(r.draft, accountId),
        }
    ];

    setState(() {
      _step = _Step.importing;
      _importDone = 0;
      _importTotal = picked.length;
      _settled = 0;
    });
    try {
      final m = Mutations(Actor.fromUser(user));
      // Due settlements first — each materializes the due's lines (scaled for
      // partials) and flips the due's status, exactly like Record payment.
      var done = 0;
      for (final r in settleRows) {
        Due? due;
        for (final d in data.dues) {
          if (d.id == r.matchedDueId) {
            due = d;
            break;
          }
        }
        if (due == null) continue;
        final amount = r.draft.amount!.abs();
        final newSettled = data.settledOf(due.id) + amount;
        final draft = buildDueSettlement(due, amount, data.debtsById,
            lineIdSeed: r.draft.date!.microsecondsSinceEpoch + done);
        await m.settleDue(
          ws,
          due.id,
          date: r.draft.date!,
          note: _noteOf(r.draft) ?? due.title,
          accountId: accountId,
          contactId: due.contactId,
          totalAmount: draft.signedTotal,
          financialYear: financialYearOf(r.draft.date!, fyStart),
          lines: draft.lines,
          newStatus: dueStatusFromSettled(due, newSettled),
          importKey: _fingerprintOf(r.draft, accountId),
        );
        done++;
        if (mounted) setState(() => _importDone = done);
      }
      final settledCount = done;

      final n = records.isEmpty
          ? 0
          : await m.importTransactions(
              ws,
              accountId: accountId,
              records: records,
              financialYearOf: (d) => financialYearOf(d, fyStart),
              onProgress: (bulkDone, total) {
                if (mounted) setState(() => _importDone = settledCount + bulkDone);
              },
            );
      // Next month's import starts pre-configured.
      await _saveProfile();
      if (mounted) {
        setState(() {
          _imported = settledCount + n;
          _settled = settledCount;
          _step = _Step.done;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _step = _Step.review);
        _showError('Import failed: $e\n\nNothing beyond the reported progress '
            'was written — you can safely retry; already-imported rows will be '
            'flagged as duplicates.');
      }
    }
  }

  String? _noteOf(ImportRowDraft d) {
    final desc = d.description.trim();
    if (desc.isNotEmpty) return desc;
    return d.reference.trim().isEmpty ? null : d.reference.trim();
  }

  // ---- build ---------------------------------------------------------------

  /// Leaving mid-flow (mapping/review) throws away analysis and row choices, so
  /// guard the back gesture there. Picking and the final screen leave freely;
  /// during the write we block back so the import isn't interrupted.
  bool get _canLeaveFreely => _step == _Step.pick || _step == _Step.done;

  Future<void> _confirmLeave() async {
    if (_step == _Step.importing) return; // don't interrupt the write
    final leave = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard import?'),
        content: const Text(
            'Your column mapping and row selections will be lost. The imported '
            'transactions so far (if any) are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final canCreate = ws.can('transactions.create');
    return PopScope(
      canPop: _canLeaveFreely || !canCreate,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Import statement'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: switch (_step) {
                _Step.pick => 0.25,
                _Step.mapping => 0.5,
                _Step.review => 0.75,
                _Step.importing || _Step.done => 1.0,
              },
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
        body: !canCreate
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text("Your role doesn't allow creating transactions."),
                ),
              )
            : switch (_step) {
                _Step.pick => _buildPick(),
                _Step.mapping => _buildMapping(),
                _Step.review => _buildReviewList(),
                _Step.importing => _buildImporting(),
                _Step.done => _buildDone(),
              },
      ),
    );
  }

  // ---- UI: pick ------------------------------------------------------------

  Widget _buildPick() {
    final data = context.watch<DataController>();
    final cs = Theme.of(context).colorScheme;
    final accounts = [...data.accounts]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final validAccount = accounts.any((a) => a.id == _accountId) ? _accountId : null;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Pull transactions from a bank statement into an account. '
            'Everything is read on this device — nothing is uploaded anywhere.'),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          value: validAccount,
          decoration: const InputDecoration(labelText: 'Import into account'),
          items: [
            for (final a in accounts)
              DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _accountId = v),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: validAccount == null || _busy ? null : _pickFile,
          icon: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: Text(_busy ? 'Analysing…' : 'Choose statement file'),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Supported files',
                  style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 8),
              _hint(Icons.table_chart_outlined, 'CSV and Excel — .xlsx and legacy .xls'),
              _hint(Icons.picture_as_pdf_outlined, 'PDF bank statements'),
              _hint(Icons.lock_outline,
                  'Password-protected PDF and Excel supported — you\'ll be asked for the password'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hint(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
        ],
      ),
    );
  }

  // ---- UI: mapping ---------------------------------------------------------

  String _colLabel(int i) {
    final grid = _grid!;
    final header = i < grid.header.length ? grid.header[i].trim() : '';
    // First non-empty sample from that column, for context.
    var sample = '';
    for (final r in grid.dataRows) {
      if (i < r.length && r[i].trim().isNotEmpty) {
        sample = r[i].trim();
        break;
      }
    }
    final name = header.isEmpty ? 'Column ${i + 1}' : header;
    if (sample.isEmpty) return name;
    if (sample.length > 24) sample = '${sample.substring(0, 24)}…';
    return '$name  ·  $sample';
  }

  Widget _colDropdown({
    required String label,
    required int? value,
    required void Function(int?) onChanged,
    bool clearable = true,
  }) {
    final width = _grid!.header.length;
    final valid = value != null && value >= 0 && value < width ? value : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<int>(
        value: valid,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          if (clearable)
            const DropdownMenuItem<int>(value: -1, child: Text('— not present —')),
          for (var i = 0; i < width; i++)
            DropdownMenuItem(
                value: i, child: Text(_colLabel(i), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => onChanged(v == -1 ? null : v),
      ),
    );
  }

  Widget _buildMapping() {
    final grid = _grid!;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Icon(Icons.description_outlined, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$_fileName — ${grid.dataRows.length} rows found',
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _profileApplied
              ? 'Applied your saved mapping for this account — adjust if the bank changed its format.'
              : 'Match the statement\'s columns. We\'ve guessed from the headers — adjust if needed.',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        if (_profileApplied) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.bookmark_added_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text('Saved mapping applied',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cs.primary)),
            ],
          ),
        ],
        const SizedBox(height: 18),
        _colDropdown(
          label: 'Date column',
          value: _mapping.date,
          clearable: false,
          onChanged: (v) => setState(() {
            _mapping.date = v;
            if (v != null) {
              _dateOrder =
                  detectDateOrder(grid.dataRows.take(50).map((r) => v < r.length ? r[v] : ''));
            }
          }),
        ),
        DropdownButtonFormField<DateOrder>(
          value: _dateOrder,
          decoration: const InputDecoration(labelText: 'Date format'),
          items: const [
            DropdownMenuItem(value: DateOrder.dmy, child: Text('Day / Month / Year')),
            DropdownMenuItem(value: DateOrder.mdy, child: Text('Month / Day / Year')),
            DropdownMenuItem(value: DateOrder.ymd, child: Text('Year / Month / Day')),
          ],
          onChanged: (v) => setState(() => _dateOrder = v ?? DateOrder.dmy),
        ),
        const SizedBox(height: 14),
        _colDropdown(
          label: 'Description column',
          value: _mapping.description,
          onChanged: (v) => setState(() => _mapping.description = v),
        ),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Debit + credit columns')),
            ButtonSegment(value: false, label: Text('Single amount column')),
          ],
          selected: {_mapping.splitAmounts},
          onSelectionChanged: (sel) => setState(() {
            final suggested = suggestMapping(grid.header);
            if (sel.first) {
              // Debit + credit mode: drop the single-amount column and
              // re-suggest the pair from headers (default to column 1 so the
              // mode sticks even when the guess finds nothing).
              _mapping.amount = null;
              _mapping.debit = suggested.debit ?? 0;
              _mapping.credit = suggested.credit;
            } else {
              _mapping.debit = null;
              _mapping.credit = null;
              _mapping.amount = suggested.amount ?? 0;
            }
          }),
        ),
        const SizedBox(height: 14),
        if (_mapping.splitAmounts) ...[
          _colDropdown(
            label: 'Debit (money out) column',
            value: _mapping.debit,
            onChanged: (v) => setState(() => _mapping.debit = v),
          ),
          _colDropdown(
            label: 'Credit (money in) column',
            value: _mapping.credit,
            onChanged: (v) => setState(() => _mapping.credit = v),
          ),
        ] else
          _colDropdown(
            label: 'Amount column',
            value: _mapping.amount,
            clearable: false,
            onChanged: (v) => setState(() => _mapping.amount = v),
          ),
        _colDropdown(
          label: 'Reference column (optional)',
          value: _mapping.reference,
          onChanged: (v) => setState(() => _mapping.reference = v),
        ),
        _colDropdown(
          label: 'Balance column (optional — enables reconciliation)',
          value: _mapping.balance,
          onChanged: (v) => setState(() => _mapping.balance = v),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _step = _Step.pick),
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _mapping.complete ? _buildReview : null,
                child: const Text('Continue to review'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---- UI: review ----------------------------------------------------------

  Widget _buildReviewList() {
    final ws = context.watch<WorkspaceController>();
    final data = context.watch<DataController>();
    final cs = Theme.of(context).colorScheme;
    final currency = ws.activeWorkspace?.baseCurrency ?? 'INR';

    final selected = _rows.where((r) => r.selected).toList();
    var totalIn = 0.0, totalOut = 0.0;
    for (final r in selected) {
      final a = r.draft.amount!;
      if (a >= 0) {
        totalIn += a;
      } else {
        totalOut += -a;
      }
    }
    final readable = _rows.where((r) => r.draft.parseable).toList();
    final dupCount = _rows.where((r) => r.duplicate).length;
    final unreadable = _rows.length - readable.length;
    final expenseCats =
        data.categories.where((c) => c.kind == 'expense').toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final incomeCats = data.categories.where((c) => c.kind == 'income').toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${selected.length} of ${readable.length} rows selected'
                      '${dupCount > 0 ? ' · $dupCount duplicate${dupCount == 1 ? '' : 's'}' : ''}'
                      '${unreadable > 0 ? ' · $unreadable to fix' : ''}',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ),
                  TextButton(
                    onPressed: readable.isEmpty
                        ? null
                        : () => setState(() {
                              final all = readable.every((r) => r.selected);
                              for (final r in readable) {
                                r.selected = !all;
                              }
                            }),
                    child: Text(
                        readable.isNotEmpty && readable.every((r) => r.selected) ? 'None' : 'All'),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _miniCatDropdown('Money-out category', expenseCats,
                        _defaultExpenseCat, (v) => setState(() => _defaultExpenseCat = v)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _miniCatDropdown('Money-in category', incomeCats, _defaultIncomeCat,
                        (v) => setState(() => _defaultIncomeCat = v)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<_DupMode>(
                value: _dupMode,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Flag duplicates by', isDense: true),
                items: const [
                  DropdownMenuItem(
                      value: _DupMode.strict,
                      child: Text('Date + amount + reference/description')),
                  DropdownMenuItem(value: _DupMode.dateAmount, child: Text('Date + amount only')),
                  DropdownMenuItem(value: _DupMode.off, child: Text("Don't flag duplicates")),
                ],
                onChanged: (v) => setState(() {
                  _dupMode = v ?? _DupMode.strict;
                  // Re-flag and reset selection to the new criterion.
                  _applyDupMode();
                }),
              ),
              _reconciliationCard(data, currency, selected),
              const SizedBox(height: 6),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No readable transaction rows. Go back and check the column mapping.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) => _reviewRowTile(_rows[i], currency),
                ),
        ),
        const Divider(height: 1),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _step = _Step.mapping),
                  child: const Text('Back'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('In ${formatMoney(totalIn, currency)} · Out ${formatMoney(totalOut, currency)}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: selected.isEmpty ? null : _import,
                  child: Text('Import ${selected.length}'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Statement closing balance (row with the latest date that carries one) vs
  /// the app's balance after importing the current selection. A zero delta is
  /// the strongest signal the account is fully reconciled; a non-zero one
  /// means unticked rows, missing older history, or duplicates.
  Widget _reconciliationCard(DataController data, String currency, List<_ReviewRow> selected) {
    final accountId = _accountId;
    if (_mapping.balance == null || accountId == null) return const SizedBox.shrink();
    ImportRowDraft? closing;
    for (final r in _rows) {
      final d = r.draft;
      if (d.date == null || d.balance == null) continue;
      if (closing == null || d.date!.isAfter(closing.date!)) closing = d;
    }
    if (closing == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    var projected = data.balanceOf(accountId);
    for (final r in selected) {
      projected += r.draft.amount!;
    }
    projected = roundMoney(projected);
    final statement = closing.balance!;
    final delta = roundMoney(projected - statement);
    final matched = delta.abs() < 0.01;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: (matched ? AppColors.accent2 : cs.tertiary).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (matched ? AppColors.accent2 : cs.tertiary).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(matched ? Icons.verified_outlined : Icons.difference_outlined,
              size: 18, color: matched ? AppColors.accent2 : cs.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              matched
                  ? 'Reconciled: after import, this account will match the '
                      'statement closing balance (${formatMoney(statement, currency)}).'
                  : 'Statement closes at ${formatMoney(statement, currency)}; after '
                      'import the app shows ${formatMoney(projected, currency)} '
                      '(${delta > 0 ? '+' : ''}${formatMoney(delta, currency)}). Unticked '
                      'rows or missing older history can explain the gap.',
              style: TextStyle(fontSize: 12, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniCatDropdown(String label, List<AppCategory> cats, String? value,
      void Function(String?) onChanged) {
    final valid = cats.any((c) => c.id == value) ? value : null;
    return DropdownButtonFormField<String>(
      value: valid,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('Uncategorised')),
        for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }

  Widget _reviewRowTile(_ReviewRow row, String currency) {
    final cs = Theme.of(context).colorScheme;
    final data = context.read<DataController>();
    final d = row.draft;
    final amount = d.amount;
    String? dueTitle;
    if (row.matchedDueId != null) {
      for (final due in data.dues) {
        if (due.id == row.matchedDueId) {
          dueTitle = due.title;
          break;
        }
      }
    }
    String? catName;
    if (row.categorySuggested && row.categoryId != null) {
      for (final c in data.categories) {
        if (c.id == row.categoryId) {
          catName = c.name;
          break;
        }
      }
    }
    return InkWell(
      onTap: () => _editRow(row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: row.selected,
              onChanged: d.parseable
                  ? (v) => setState(() => row.selected = v ?? false)
                  : null,
            ),
            SizedBox(
              width: 64,
              child: Text(d.date != null ? _dateFmt.format(d.date!) : '—',
                  style: const TextStyle(fontSize: 12.5)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.description.isEmpty
                        ? (d.reference.isEmpty ? '(no description)' : d.reference)
                        : d.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (!d.parseable)
                    Text(
                      d.date == null
                          ? 'No readable date — tap to fix'
                          : 'No readable amount — tap to fix',
                      style: TextStyle(fontSize: 11, color: cs.error),
                    )
                  else if (row.duplicate)
                    Text('Duplicate — already in this account',
                        style: TextStyle(fontSize: 11, color: cs.tertiary)),
                  if (dueTitle != null)
                    GestureDetector(
                      onTap: () => setState(() => row.linkDue = !row.linkDue),
                      child: Text(
                        row.linkDue
                            ? '✓ Settles due: $dueTitle (tap to unlink)'
                            : 'Matches due: $dueTitle (tap to link)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: row.linkDue ? AppColors.accent2 : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  // Settlement rows take their lines from the due, so the
                  // learned category only applies to plain rows.
                  if (catName != null && !row.linkDue)
                    Text('Category: $catName (from your history)',
                        style: TextStyle(fontSize: 11, color: cs.primary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amount != null ? formatMoney(amount.abs(), currency) : '—',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: amount == null
                    ? cs.onSurfaceVariant
                    : (amount >= 0 ? AppColors.accent2 : AppColors.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Per-row override dialog: date, description, amount, direction, category.
  Future<void> _editRow(_ReviewRow row) async {
    final data = context.read<DataController>();
    final d = row.draft;
    var date = d.date ?? DateTime.now();
    var isCredit = (d.amount ?? -1) >= 0;
    final descCtl = TextEditingController(text: d.description);
    final amtCtl = TextEditingController(text: d.amount?.abs().toStringAsFixed(2) ?? '');
    var categoryId = row.categoryId;

    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final cats = (isCredit
              ? data.categories.where((c) => c.kind == 'income')
              : data.categories.where((c) => c.kind == 'expense'))
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          final validCat = cats.any((c) => c.id == categoryId) ? categoryId : null;
          return AlertDialog(
            title: const Text('Edit row'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setDlg(() => date = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date'),
                      child: Text(DateFormat('dd MMM yyyy').format(date)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtl,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amtCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Money out')),
                      ButtonSegment(value: true, label: Text('Money in')),
                    ],
                    selected: {isCredit},
                    onSelectionChanged: (s) => setDlg(() {
                      isCredit = s.first;
                      categoryId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: validCat,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('Default')),
                      for (final c in cats)
                        DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setDlg(() => categoryId = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      final parsed = double.tryParse(amtCtl.text.replaceAll(',', ''));
      setState(() {
        final wasUnreadable = !d.parseable;
        d.date = date;
        d.description = descCtl.text.trim();
        if (parsed != null && parsed > 0) {
          d.amount = isCredit ? parsed : -parsed;
        }
        row.categoryId = categoryId;
        row.categorySuggested = false; // the user has reviewed this row

        // Fixing a row can change its duplicate status — and a just-fixed
        // unreadable row should become selectable (selected unless duplicate).
        if (d.parseable) {
          row.duplicate = _isDuplicate(d);
          if (wasUnreadable) row.selected = !row.duplicate;
          // An edited amount may no longer settle the matched due exactly.
          if (row.matchedDueId != null && row.linkDue) {
            Due? due;
            for (final x in data.dues) {
              if (x.id == row.matchedDueId) {
                due = x;
                break;
              }
            }
            if (due != null) {
              final remaining = due.amount - data.settledOf(due.id);
              if ((d.amount!.abs() - remaining).abs() > 0.01) row.linkDue = false;
            }
          }
        }
      });
    }
    descCtl.dispose();
    amtCtl.dispose();
  }

  // ---- UI: importing / done ------------------------------------------------

  Widget _buildImporting() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text('Importing $_importDone of $_importTotal…'),
        ],
      ),
    );
  }

  Widget _buildDone() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.accent2.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 40, color: AppColors.accent2),
            ),
            const SizedBox(height: 18),
            Text('$_imported transaction${_imported == 1 ? '' : 's'} imported',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
                _settled > 0
                    ? '$_settled due${_settled == 1 ? '' : 's'} settled along the way. '
                        'They\'re in the account ledger now.'
                    : 'They\'re in the account ledger now.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('View ledger'),
              onPressed: () {
                if (_accountId != null) {
                  context.pushReplacement('/accounts/$_accountId/ledger');
                } else {
                  context.pop();
                }
              },
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: () => context.pop(), child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
