// Card-based list with per-card show/hide fields (persisted) and sorting.
// Replaces the dense DataTableView on list screens — cards read better on a
// phone. Each row is a tappable card: a title line, an optional prominent
// amount, and a wrap of secondary "label · value" fields the user can toggle
// via the "Fields" menu. Visibility is persisted per list id (reuses
// ColumnPrefs' hidden-set), so a user's choices stick across sessions.

import 'package:flutter/material.dart';

import '../core/column_prefs.dart';

enum CardRole { title, amount, meta }

class CardField<T> {
  final String key;
  final String label;

  /// Text value for the field. Ignored when [widget] is provided.
  final String Function(T row)? text;

  /// Custom widget for the field (e.g. a coloured amount). Overrides [text].
  final Widget Function(T row)? widget;

  /// Optional value used when this field is the active sort key.
  final Comparable Function(T row)? sortValue;

  final CardRole role;

  /// Locked fields (usually the title) are always shown and can't be hidden.
  final bool locked;
  final bool defaultVisible;

  const CardField({
    required this.key,
    required this.label,
    this.text,
    this.widget,
    this.sortValue,
    this.role = CardRole.meta,
    this.locked = false,
    this.defaultVisible = true,
  });
}

class EntityCardList<T> extends StatefulWidget {
  final String listId;
  final List<CardField<T>> fields;
  final List<T> rows;
  final void Function(T row)? onRowTap;

  /// Leading widget (e.g. an avatar) rendered at the start of each card.
  final Widget Function(T row)? leading;

  /// Trailing widget (e.g. a row action menu) at the end of each card.
  final Widget Function(T row)? trailing;

  /// Extra padding around the list (screens with their own toolbar can zero this).
  final EdgeInsets padding;

  const EntityCardList({
    super.key,
    required this.listId,
    required this.fields,
    required this.rows,
    this.onRowTap,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 96),
  });

  @override
  State<EntityCardList<T>> createState() => _EntityCardListState<T>();
}

class _EntityCardListState<T> extends State<EntityCardList<T>> {
  Set<String> _hidden = {};
  String? _sortKey;
  bool _asc = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Default sort: the amount/first sortable field, descending.
    final sortable = widget.fields.where((f) => f.sortValue != null).toList();
    if (sortable.isNotEmpty) {
      _sortKey = (sortable.firstWhere(
        (f) => f.role == CardRole.amount,
        orElse: () => sortable.first,
      )).key;
    }
    _load();
  }

  Future<void> _load() async {
    final prefs = await ColumnPrefs.load(widget.listId);
    if (!mounted) return;
    setState(() {
      _hidden = prefs.hidden;
      _loaded = true;
    });
  }

  Future<void> _persist() async {
    await ColumnPrefs(_hidden, const {}).save(widget.listId);
  }

  bool _visible(CardField<T> f) => f.locked || !_hidden.contains(f.key);

  List<T> get _sorted {
    final rows = [...widget.rows];
    final f = _sortKey == null ? null : widget.fields.firstWhere((e) => e.key == _sortKey);
    if (f?.sortValue != null) {
      rows.sort((a, b) => f!.sortValue!(a).compareTo(f.sortValue!(b)));
      if (!_asc) {
        final r = rows.reversed.toList();
        return r;
      }
    }
    return rows;
  }

  void _openFieldsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            void toggle(CardField<T> f, bool on) {
              setState(() {
                if (on) {
                  _hidden.remove(f.key);
                } else {
                  _hidden.add(f.key);
                }
              });
              setSheet(() {});
              _persist();
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text('Shown fields', style: Theme.of(ctx).textTheme.titleMedium),
                ),
                for (final f in widget.fields.where((f) => f.role != CardRole.title))
                  SwitchListTile(
                    dense: true,
                    value: _visible(f),
                    onChanged: f.locked ? null : (v) => toggle(f, v),
                    title: Text(f.label),
                    secondary: f.locked ? const Icon(Icons.lock_outline, size: 18) : null,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _hidden = widget.fields
                          .where((f) => !f.defaultVisible)
                          .map((f) => f.key)
                          .toSet());
                      setSheet(() {});
                      _persist();
                    },
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reset to defaults'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final rows = _sorted;
    final sortable = widget.fields.where((f) => f.sortValue != null).toList();

    return Column(
      children: [
        _toolbar(context, sortable),
        Expanded(
          child: ListView.separated(
            padding: widget.padding,
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _card(context, rows[i]),
          ),
        ),
      ],
    );
  }

  Widget _toolbar(BuildContext context, List<CardField<T>> sortable) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      child: Row(
        children: [
          if (sortable.isNotEmpty) ...[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openSortMenu(context, sortable),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_asc ? Icons.arrow_upward : Icons.arrow_downward, size: 15, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'Sort: ${widget.fields.firstWhere((f) => f.key == _sortKey, orElse: () => sortable.first).label}',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: _openFieldsSheet,
            icon: const Icon(Icons.tune, size: 17),
            label: const Text('Fields'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _openSortMenu(BuildContext context, List<CardField<T>> sortable) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Sort by', style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final f in sortable)
              RadioListTile<String>(
                dense: true,
                value: f.key,
                groupValue: _sortKey,
                onChanged: (v) {
                  setState(() => _sortKey = v);
                  Navigator.pop(ctx);
                },
                title: Text(f.label),
              ),
            const Divider(height: 1),
            SwitchListTile(
              dense: true,
              value: _asc,
              onChanged: (v) {
                setState(() => _asc = v);
                Navigator.pop(ctx);
              },
              title: const Text('Ascending order'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, T row) {
    final cs = Theme.of(context).colorScheme;
    final titleField = widget.fields.where((f) => f.role == CardRole.title && _visible(f)).toList();
    final amountField = widget.fields.where((f) => f.role == CardRole.amount && _visible(f)).toList();
    final metaFields = widget.fields.where((f) => f.role == CardRole.meta && _visible(f)).toList();

    Widget fieldValue(CardField<T> f) => f.widget != null ? f.widget!(row) : Text(f.text?.call(row) ?? '');

    return Card(
      child: InkWell(
        onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.leading != null) ...[
                widget.leading!(row),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DefaultTextStyle.merge(
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            child: titleField.isNotEmpty
                                ? fieldValue(titleField.first)
                                : const SizedBox.shrink(),
                          ),
                        ),
                        if (amountField.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          DefaultTextStyle.merge(
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            child: fieldValue(amountField.first),
                          ),
                        ],
                      ],
                    ),
                    if (metaFields.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          for (final f in metaFields)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${f.label}  ',
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                DefaultTextStyle.merge(
                                  style: TextStyle(fontSize: 12.5, color: cs.onSurface),
                                  child: fieldValue(f),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) widget.trailing!(row),
            ],
          ),
        ),
      ),
    );
  }
}
