import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../services/title_tokens.dart';

/// The chips-and-preview strip that turns a plain title into a pattern.
///
/// It only ever appears once a form has a repeat set, because that is the only
/// moment the distinction matters: a one-off due's title is used once, so
/// there is nothing to fill in. The preview renders THIS entry's own date —
/// the one in the form above it — so what you read in the preview is exactly
/// what the entry you are saving will be called.
class TokenAssist extends StatefulWidget {
  final TextEditingController controller;

  /// The date of the entry being edited: its due date, or a transaction's
  /// date. Change the date in the form and the preview follows it.
  final DateTime date;
  final int fyStartMonth;

  /// Which occurrence of the series this entry is, for `{#}`.
  final int occurrence;

  /// Label in front of the preview, e.g. "Shows as" or "Note shows as".
  final String previewLabel;

  const TokenAssist({
    super.key,
    required this.controller,
    required this.date,
    required this.fyStartMonth,
    this.occurrence = 1,
    this.previewLabel = 'Shows as',
  });

  @override
  State<TokenAssist> createState() => _TokenAssistState();
}

class _TokenAssistState extends State<TokenAssist> {
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

  void _insert(String token) {
    final sel = widget.controller.selection;
    final at = sel.isValid ? sel.start : widget.controller.text.length;
    final r = insertToken(widget.controller.text, at, token);
    widget.controller.value = TextEditingValue(
      text: r.text,
      selection: TextSelection.collapsed(offset: r.cursor),
    );
    HapticFeedback.selectionClick();
  }

  Future<void> _showAll() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _TokenCatalogue(
        date: widget.date,
        fyStartMonth: widget.fyStartMonth,
        occurrence: widget.occurrence,
      ),
    );
    if (picked != null) _insert(picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = widget.controller.text;
    final preview =
        renderTokens(text, widget.date, occurrence: widget.occurrence, fyStartMonth: widget.fyStartMonth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        // A wrap, not a scroll strip: on a 360dp phone the last chip would sit
        // off the right edge, and a chip nobody can see is a chip nobody taps.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final spec in kTitleTokens.take(kPrimaryTokenCount))
              _TokenChip(label: spec.label, onTap: () => _insert(spec.token)),
            _TokenChip(label: 'More', trailing: Icons.expand_more, onTap: _showAll),
          ],
        ),
        if (hasTokens(text)) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.autorenew, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${widget.previewLabel}: $preview',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TokenChip extends StatelessWidget {
  final String label;
  final IconData? trailing;
  final VoidCallback onTap;
  const _TokenChip({required this.label, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 12.5, color: cs.onSurface)),
              if (trailing != null) ...[
                const SizedBox(width: 2),
                Icon(trailing, size: 15, color: cs.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The full list behind "More", with each token rendered for the real date so
/// the example is never stale, plus the one thing the chips cannot express:
/// offsets, for people whose RD title names the month being paid for.
class _TokenCatalogue extends StatelessWidget {
  final DateTime date;
  final int fyStartMonth;
  final int occurrence;
  const _TokenCatalogue({
    required this.date,
    required this.fyStartMonth,
    required this.occurrence,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: cs.primary,
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
                  'Rendered here for this entry, dated ${formatDate(date)}. Each later one fills itself in with its own date. Tap to insert.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                for (final spec in kTitleTokens)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Row(
                      children: [
                        Text(spec.token, style: mono),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            renderTokens(spec.token, date,
                                occurrence: occurrence, fyStartMonth: fyStartMonth),
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    subtitle:
                        Text(spec.description, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    onTap: () => Navigator.of(context).pop(spec.token),
                  ),
                const Divider(height: 24),
                Text('Shift it', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  'Add +1 or -1 inside a placeholder to move it. Handy when the title names the period being paid for rather than the payment date.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                for (final example in const ['{MMM-1}', '{MMM+1}', '{YYYY-1}'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Text(example, style: mono),
                        const SizedBox(width: 8),
                        Text(renderTokens(example, date, occurrence: occurrence, fyStartMonth: fyStartMonth),
                            style: const TextStyle(fontSize: 13)),
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
