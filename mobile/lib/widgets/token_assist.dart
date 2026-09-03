import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../services/title_tokens.dart';
import 'common.dart';

/// A text field that can carry placeholders, for the title and note of an
/// entry that repeats.
///
/// The placeholder affordance lives INSIDE the field: a button in the trailing
/// slot opens the picker, and the field's own helper line says what the entry
/// will be called. Nothing is added to the form's layout — a row of chips and
/// a preview line under every field turned two inputs into six rows of
/// furniture, which is most of the form for something most entries never use.
///
/// With [repeats] false this is an ordinary text field, down to the pixel: no
/// button, no helper line, no reserved space.
class TokenTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;

  /// Whether this entry repeats. Placeholders only matter then: a one-off
  /// title is used once, so there is nothing to fill in.
  final bool repeats;

  /// The date of the entry being edited — its due date, or a transaction's
  /// date. The preview renders this, so it reads what saving will store, and
  /// it follows the date field when that changes.
  final DateTime date;

  /// Which occurrence of the series this entry is, for `{#}`.
  final int occurrence;
  final int fyStartMonth;
  final TextCapitalization textCapitalization;

  const TokenTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.repeats,
    required this.date,
    required this.fyStartMonth,
    this.occurrence = 1,
    this.validator,
    this.textCapitalization = TextCapitalization.sentences,
  });

  @override
  State<TokenTextField> createState() => _TokenTextFieldState();
}

class _TokenTextFieldState extends State<TokenTextField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pick() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TokenCatalogue(
        date: widget.date,
        fyStartMonth: widget.fyStartMonth,
        occurrence: widget.occurrence,
      ),
    );
    if (picked == null) return;
    // Insert at the caret rather than at the end — the difference between the
    // picker being useful and being a nuisance.
    final sel = widget.controller.selection;
    final at = sel.isValid ? sel.start : widget.controller.text.length;
    final r = insertToken(widget.controller.text, at, picked);
    widget.controller.value = TextEditingValue(
      text: r.text,
      selection: TextSelection.collapsed(offset: r.cursor),
    );
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    String? helper;
    if (widget.repeats) {
      helper = hasTokens(text)
          ? 'Shows as: ${renderTokens(text, widget.date, occurrence: widget.occurrence, fyStartMonth: widget.fyStartMonth)}'
          // Without this the button is a cryptic glyph nobody presses.
          : 'Add a placeholder so every repeat dates itself';
    }

    return TextFormField(
      controller: widget.controller,
      validator: widget.validator,
      textCapitalization: widget.textCapitalization,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: helper,
        helperMaxLines: 2,
        suffixIcon: widget.repeats
            ? IconButton(
                icon: const Icon(Icons.data_object, size: 20),
                tooltip: 'Insert placeholder',
                onPressed: _pick,
              )
            : null,
      ),
    );
  }
}

/// The picker: every placeholder rendered for this entry's real date, so the
/// examples cannot go stale, plus the one thing a list cannot show — offsets,
/// for a title that names the period being paid for rather than the pay date.
class _TokenCatalogue extends StatelessWidget {
  final DateTime date;
  final int fyStartMonth;
  final int occurrence;
  const _TokenCatalogue({
    required this.date,
    required this.fyStartMonth,
    required this.occurrence,
  });

  String _render(String pattern) =>
      renderTokens(pattern, date, occurrence: occurrence, fyStartMonth: fyStartMonth);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 13, color: cs.primary);

    Widget row(String token, String description) => ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Row(
            children: [
              SizedBox(width: 76, child: Text(token, style: mono)),
              Expanded(
                child: Text(
                  _render(token),
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Text(description, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          onTap: () => Navigator.of(context).pop(token),
        );

    // Capped rather than left to size itself: the full list is taller than a
    // phone, and an uncapped sheet lays its tail out below the screen where
    // scrolling cannot reach it.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Placeholders', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Every repeat fills these in with its own date. Shown here for '
                  '${formatDate(date)}.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                for (final spec in kTitleTokens.take(kPrimaryTokenCount)) row(spec.token, spec.description),
                const SizedBox(height: 12),
                const SectionLabel('More'),
                for (final spec in kTitleTokens.skip(kPrimaryTokenCount)) row(spec.token, spec.description),
                const SizedBox(height: 16),
                const SectionLabel('Shift it'),
                Text(
                  'Add +1 or -1 inside a placeholder to move it. Handy when the title names '
                  'the period being paid for rather than the payment date.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                for (final example in const ['{MMM-1}', '{MMM+1}', '{YYYY-1}'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(width: 76, child: Text(example, style: mono)),
                        Text(_render(example), style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
