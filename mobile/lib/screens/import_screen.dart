import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/derive.dart';
import '../data/models.dart';
import '../data/mutations.dart';
import '../services/statement_parser.dart';
import '../state/auth_controller.dart';
import '../state/data_controller.dart';
import '../state/workspace_controller.dart';

/// Statement import — upload → analyse (password prompt for encrypted PDFs) →
/// map columns → review rows in a table with checkboxes and per-row edits →
/// import. All parsing happens on-device; passwords stay in memory only.
class ImportScreen extends StatefulWidget {
  final String? initialAccountId;
  const ImportScreen({super.key, this.initialAccountId});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

enum _Step { pick, mapping, review, importing, done }

/// A parsed statement row plus the review screen's state for it.
class _ReviewRow {
  final ImportRowDraft draft;
  bool selected;
  bool duplicate;
  String? categoryId; // per-row override; falls back to the defaults
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

  // Review state.
  List<_ReviewRow> _rows = [];
  int _unparseable = 0;
  String? _defaultExpenseCat;
  String? _defaultIncomeCat;

  // Import progress.
  int _importDone = 0;
  int _importTotal = 0;
  int _imported = 0;

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

  Future<void> _analyze(Uint8List bytes, String name, {String? password}) async {
    setState(() => _busy = true);
    try {
      // Let the spinner paint before the (synchronous) parse work.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final grid = parseStatement(bytes, name, password: password);
      final mapping = suggestMapping(grid.header);
      var order = DateOrder.dmy;
      if (mapping.date != null) {
        order = detectDateOrder(
            grid.dataRows.take(50).map((r) => mapping.date! < r.length ? r[mapping.date!] : ''));
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
      setState(() => _busy = false);
      final pw = await _askPassword(wrongPassword: e.wrongPassword);
      if (pw != null && mounted) await _analyze(bytes, name, password: pw);
    } on StatementUnsupported catch (e) {
      setState(() => _busy = false);
      _showError(e.message);
    } catch (e) {
      setState(() => _busy = false);
      _showError("Couldn't analyse this file: $e");
    }
  }

  Future<String?> _askPassword({required bool wrongPassword}) {
    final controller = TextEditingController();
    var obscure = true;
    return showDialog<String>(
      context: context,
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
              const SizedBox(height: 8),
              Text(
                'Used only to open the file on this device — never stored.',
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

  // ---- step 2 → 3: build review rows --------------------------------------

  void _buildReview() {
    final grid = _grid;
    final accountId = _accountId;
    if (grid == null || accountId == null || !_mapping.complete) return;
    final data = context.read<DataController>();

    final drafts = buildImportRows(grid, _mapping, _dateOrder);
    // Identity of everything already in this account: stored importKeys plus
    // recomputed fingerprints, so both prior imports and manual entries match.
    final existing = <String>{};
    for (final t in data.transactions) {
      if (t.accountId != accountId) continue;
      if (t.importKey != null && t.importKey!.isNotEmpty) existing.add(t.importKey!);
      existing.add(importFingerprint(
        accountId: accountId,
        date: t.date,
        amount: t.totalAmount,
        refOrDesc: t.note ?? '',
      ));
    }

    final rows = <_ReviewRow>[];
    var unparseable = 0;
    for (final d in drafts) {
      if (!d.parseable) {
        unparseable++;
        continue;
      }
      final dup = existing.contains(_fingerprintOf(d, accountId));
      rows.add(_ReviewRow(d, selected: !dup, duplicate: dup));
    }
    setState(() {
      _rows = rows;
      _unparseable = unparseable;
      _step = _Step.review;
    });
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

    final records = <Map<String, dynamic>>[
      for (final r in picked)
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
      _importTotal = records.length;
    });
    try {
      final n = await Mutations(Actor.fromUser(user)).importTransactions(
        ws,
        accountId: accountId,
        records: records,
        financialYearOf: (d) => financialYearOf(d, fyStart),
        onProgress: (done, total) {
          if (mounted) setState(() => _importDone = done);
        },
      );
      if (mounted) {
        setState(() {
          _imported = n;
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

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WorkspaceController>();
    final canCreate = ws.can('transactions.create');
    return Scaffold(
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
              _hint(Icons.table_chart_outlined, 'CSV / Excel (.xlsx) exports'),
              _hint(Icons.picture_as_pdf_outlined,
                  'PDF statements — password-protected ones supported'),
              _hint(Icons.lock_outline,
                  'Password-protected Excel can\'t be opened on-device — export CSV or PDF instead'),
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
          'Match the statement\'s columns. We\'ve guessed from the headers — adjust if needed.',
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
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
    final dupCount = _rows.where((r) => r.duplicate).length;
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
                      '${selected.length} of ${_rows.length} rows selected'
                      '${dupCount > 0 ? ' · $dupCount duplicate${dupCount == 1 ? '' : 's'}' : ''}'
                      '${_unparseable > 0 ? ' · $_unparseable unreadable' : ''}',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      final all = _rows.every((r) => r.selected);
                      for (final r in _rows) {
                        r.selected = !all;
                      }
                    }),
                    child: Text(_rows.every((r) => r.selected) ? 'None' : 'All'),
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
    final d = row.draft;
    final amount = d.amount!;
    return InkWell(
      onTap: () => _editRow(row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: row.selected,
              onChanged: (v) => setState(() => row.selected = v ?? false),
            ),
            SizedBox(
              width: 64,
              child: Text(_dateFmt.format(d.date!), style: const TextStyle(fontSize: 12.5)),
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
                  if (row.duplicate)
                    Text('Duplicate — already in this account',
                        style: TextStyle(fontSize: 11, color: cs.tertiary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatMoney(amount.abs(), currency),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: amount >= 0 ? AppColors.accent2 : AppColors.danger,
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
    var date = d.date!;
    var isCredit = d.amount! >= 0;
    final descCtl = TextEditingController(text: d.description);
    final amtCtl = TextEditingController(text: d.amount!.abs().toStringAsFixed(2));
    var categoryId = row.categoryId;

    final saved = await showDialog<bool>(
      context: context,
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
        d.date = date;
        d.description = descCtl.text.trim();
        if (parsed != null && parsed > 0) {
          d.amount = isCredit ? parsed : -parsed;
        }
        row.categoryId = categoryId;
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
            Text('They\'re in the account ledger now.',
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
