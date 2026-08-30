import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Visual space between a sheet's header and the form below it.
const double kSheetHeaderGap = 6;

/// Padding INSIDE a guarded form's scroll view, above its first field. The
/// app's dense outline fields paint their floating label a few pixels above
/// the field's own box, and a viewport clips whatever sits above its top
/// edge — so the first field needs slack INSIDE the scroll view. Padding
/// outside it (see [kSheetHeaderGap]) moves the viewport, not the label.
const double kSheetFieldTopPad = 8;

/// Wraps a create/edit sheet's content so closing it with unsaved edits asks
/// for confirmation first. Untouched forms close freely. Forms report their
/// state via [isDirty] — typically comparing a fingerprint of their fields
/// against one taken when the sheet opened.
///
/// Back (button or gesture) and taps on the scrim both route through
/// `Navigator.maybePop`, so [PopScope] can intercept them. A swipe down on the
/// sheet itself does NOT: Flutter's bottom sheet calls `Navigator.pop`
/// directly when the drag closes it, which skips every guard and silently
/// drops the edits. So guarded sheets are opened with `enableDrag: false` and
/// no drag handle, and this guard supplies the close button that replaces it.
/// [showCloseButton] can turn that button off for hosts that provide their own.
class DiscardGuard extends StatefulWidget {
  final bool Function() isDirty;
  final Widget child;
  final bool showCloseButton;

  /// The sheet's heading. Given here rather than inside [child] so it shares a
  /// row with the close button instead of sitting under it.
  final String? title;

  const DiscardGuard({
    super.key,
    required this.isDirty,
    required this.child,
    this.showCloseButton = true,
    this.title,
  });

  /// Closes the sheet, asking first when there are unsaved edits. Use this
  /// anywhere a guarded sheet closes itself without saving.
  static Future<void> requestClose(BuildContext context) =>
      Navigator.maybePop(context);

  @override
  State<DiscardGuard> createState() => _DiscardGuardState();
}

class _DiscardGuardState extends State<DiscardGuard> {
  // The header stays put while the form scrolls under it. Without a line to
  // scroll under, the first field just looks sliced in half, so the divider
  // appears the moment the content moves and stays away on short forms.
  bool _scrolledUnder = false;

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false; // ignore chip rows
    final under = n.metrics.pixels > 0.5;
    if (under != _scrolledUnder) setState(() => _scrolledUnder = under);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDirty = widget.isDirty;
    final title = widget.title;
    final showCloseButton = widget.showCloseButton;
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (!isDirty()) {
          nav.pop();
          return;
        }
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('You have unsaved edits. Closing now will lose them.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (discard == true) nav.pop();
      },
      child: (showCloseButton || title != null)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        // outlineVariant all but disappears on the dark theme,
                        // which left the cut edge looking like a glitch rather
                        // than a boundary.
                        color: _scrolledUnder
                            ? cs.outline.withValues(alpha: 0.6)
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: title == null
                            ? const SizedBox.shrink()
                            : Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                      ),
                      if (showCloseButton)
                        IconButton(
                          tooltip: 'Close',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => DiscardGuard.requestClose(context),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: kSheetHeaderGap),
                Flexible(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: widget.child,
                  ),
                ),
              ],
            )
          : widget.child,
    );
  }
}
