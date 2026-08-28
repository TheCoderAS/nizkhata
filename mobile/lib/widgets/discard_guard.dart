import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Wraps a create/edit sheet's content so closing it (back button or tapping
/// outside) with unsaved edits asks for confirmation first. Untouched forms
/// close freely. Forms report their state via [isDirty] — typically comparing
/// a fingerprint of their fields against one taken when the sheet opened.
class DiscardGuard extends StatelessWidget {
  final bool Function() isDirty;
  final Widget child;
  const DiscardGuard({super.key, required this.isDirty, required this.child});

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
      child: child,
    );
  }
}
