import 'package:flutter/material.dart';

import '../core/theme.dart';

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
class DiscardGuard extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: title == null
                            ? const SizedBox.shrink()
                            : Text(
                                title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                      ),
                      if (showCloseButton)
                        IconButton(
                          tooltip: 'Close',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => requestClose(context),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                ),
                Flexible(child: child),
              ],
            )
          : child,
    );
  }
}
