// Reusable data table: horizontally scrollable, with show/hide columns, drag-to-
// resize column widths (persisted per table id), tap-header sorting, and a
// sticky header. Ports the web ResizableTable + ColumnsMenu + useColumnPrefs.
//
// Usage: give it a stable [tableId], a list of [DataColumn2] definitions and the
// [rows]; optionally [onRowTap] and a per-row [trailing] builder (e.g. a kebab
// menu). Place [DataTableToolbar]'s columns button via [toolbarLeading] for a
// search/filter row, or let the built-in toolbar render just the columns menu.

import 'package:flutter/material.dart';

import '../lib/column_prefs.dart';

class DataColumn2<T> {
  final String key;
  final String label;
  final bool numeric;
  final bool locked; // cannot be hidden (e.g. the primary/name column)
  final bool defaultVisible;
  final double defaultWidth;
  final Widget Function(T row) cell;
  final Comparable Function(T row)? sortValue;
  const DataColumn2({
    required this.key,
    required this.label,
    required this.cell,
    this.numeric = false,
    this.locked = false,
    this.defaultVisible = true,
    this.defaultWidth = 130,
    this.sortValue,
  });
}

class DataTableView<T> extends StatefulWidget {
  final String tableId;
  final List<DataColumn2<T>> columns;
  final List<T> rows;
  final void Function(T row)? onRowTap;
  final Widget Function(T row)? trailing; // fixed trailing cell (not scrolled), e.g. a menu
  final double rowHeight;
  const DataTableView({
    super.key,
    required this.tableId,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.trailing,
    this.rowHeight = 52,
  });

  @override
  State<DataTableView<T>> createState() => _DataTableViewState<T>();
}

class _DataTableViewState<T> extends State<DataTableView<T>> {
  final _hidden = <String>{};
  final _widths = <String, double>{};
  String? _sortKey;
  bool _sortAsc = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ColumnPrefs.load(widget.tableId);
    if (!mounted) return;
    setState(() {
      _hidden
        ..clear()
        ..addAll(p.hidden.where((k) {
          // never persist a locked column as hidden
          final col = widget.columns.where((c) => c.key == k);
          return col.isEmpty || !col.first.locked;
        }));
      // default-hidden columns (defaultVisible == false) that the user hasn't
      // explicitly shown stay hidden on first run.
      for (final c in widget.columns) {
        if (!c.defaultVisible && !p.hidden.contains(c.key) && !_userTouched(p)) {
          _hidden.add(c.key);
        }
      }
      _widths
        ..clear()
        ..addAll(p.widths);
      _loaded = true;
    });
  }

  // Heuristic: if prefs already has any saved data, respect it verbatim.
  bool _userTouched(ColumnPrefs p) => p.hidden.isNotEmpty || p.widths.isNotEmpty;

  void _persist() {
    ColumnPrefs(_hidden, _widths).save(widget.tableId);
  }

  double _w(DataColumn2<T> c) => _widths[c.key] ?? c.defaultWidth;

  List<DataColumn2<T>> get _visible => widget.columns.where((c) => !_hidden.contains(c.key)).toList();

  List<T> get _sortedRows {
    if (_sortKey == null) return widget.rows;
    final col = widget.columns.where((c) => c.key == _sortKey);
    if (col.isEmpty || col.first.sortValue == null) return widget.rows;
    final sv = col.first.sortValue!;
    final list = [...widget.rows]..sort((a, b) => sv(a).compareTo(sv(b)));
    return _sortAsc ? list : list.reversed.toList();
  }

  void _toggleSort(DataColumn2<T> c) {
    if (c.sortValue == null) return;
    setState(() {
      if (_sortKey == c.key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortKey = c.key;
        _sortAsc = true;
      }
    });
  }

  Future<void> _openColumnsMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Columns', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              for (final c in widget.columns)
                CheckboxListTile(
                  dense: true,
                  title: Text(c.label),
                  value: !_hidden.contains(c.key),
                  onChanged: c.locked
                      ? null
                      : (v) {
                          void apply() {
                            if (v == true) {
                              _hidden.remove(c.key);
                            } else {
                              _hidden.add(c.key);
                            }
                          }

                          setSheet(apply);
                          setState(apply);
                          _persist();
                        },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset columns'),
                  onPressed: () {
                    void apply() {
                      _hidden
                        ..clear()
                        ..addAll(widget.columns.where((c) => !c.defaultVisible).map((c) => c.key));
                      _widths.clear();
                    }

                    setSheet(apply);
                    setState(apply);
                    _persist();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    final cs = Theme.of(context).colorScheme;
    final visible = _visible;
    final tableWidth = visible.fold<double>(0, (s, c) => s + _w(c)) + (widget.trailing != null ? 44 : 0);
    final rows = _sortedRows;

    return Column(
      children: [
        // toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
          child: Row(
            children: [
              Text('${rows.length} row${rows.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.view_column_outlined),
                tooltip: 'Columns',
                onPressed: _openColumnsMenu,
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final width = tableWidth < constraints.maxWidth ? constraints.maxWidth : tableWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      _headerRow(cs, visible),
                      const Divider(height: 1),
                      Expanded(
                        child: rows.isEmpty
                            ? Center(
                                child: Text('No data', style: TextStyle(color: cs.onSurfaceVariant)),
                              )
                            : ListView.separated(
                                itemCount: rows.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, i) => _bodyRow(cs, visible, rows[i]),
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _headerRow(ColorScheme cs, List<DataColumn2<T>> visible) {
    return Container(
      color: cs.surfaceContainerHigh.withValues(alpha: 0.4),
      height: 40,
      child: Row(
        children: [
          for (final c in visible) _headerCell(cs, c),
          if (widget.trailing != null) const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _headerCell(ColorScheme cs, DataColumn2<T> c) {
    final active = _sortKey == c.key;
    return SizedBox(
      width: _w(c),
      child: Stack(
        children: [
          InkWell(
            onTap: c.sortValue != null ? () => _toggleSort(c) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: c.numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      c.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (active)
                    Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: cs.primary),
                ],
              ),
            ),
          ),
          // resize handle on the right edge
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (d) {
                  setState(() => _widths[c.key] = (_w(c) + d.delta.dx).clamp(60.0, 400.0));
                },
                onHorizontalDragEnd: (_) => _persist(),
                child: Container(width: 12, alignment: Alignment.center, child: Container(width: 1, color: cs.outlineVariant)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodyRow(ColorScheme cs, List<DataColumn2<T>> visible, T row) {
    return InkWell(
      onTap: widget.onRowTap != null ? () => widget.onRowTap!(row) : null,
      child: SizedBox(
        height: widget.rowHeight,
        child: Row(
          children: [
            for (final c in visible)
              SizedBox(
                width: _w(c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Align(
                    alignment: c.numeric ? Alignment.centerRight : Alignment.centerLeft,
                    child: c.cell(row),
                  ),
                ),
              ),
            if (widget.trailing != null) SizedBox(width: 44, child: widget.trailing!(row)),
          ],
        ),
      ),
    );
  }
}
