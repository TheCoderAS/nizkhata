// A compact segmented control: one sunken track with the selected segment
// lifted out of it in an accent tint. Reads quieter than Material's
// SegmentedButton, whose outlined boxes fight with the cards around them.

import 'package:flutter/material.dart';

class SegmentedTabs<T> extends StatelessWidget {
  /// Segments in display order, as (value, label).
  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Tint for the selected segment. Defaults to the theme's primary.
  final Color? accent;

  const SegmentedTabs({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = accent ?? cs.primary;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          for (final (value, label) in segments)
            Expanded(child: _segment(context, value, label, tint)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, T value, String label, Color tint) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = value == selected;
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? tint.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? tint.withValues(alpha: 0.35) : Colors.transparent,
            ),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? tint : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
