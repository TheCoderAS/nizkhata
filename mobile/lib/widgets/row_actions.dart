// Gesture-first row actions — replaces the per-row 3-dot overflow menu.
//
// A list card wrapped in [RowActions] gets:
//  - swipe (start/end) for at most two SAFE actions (record a payment, send a
//    reminder, open the ledger). The card springs back after triggering —
//    nothing is ever dismissed, and destructive actions are never swipeable.
//  - long-press for the full action sheet (what the 3-dot menu used to hold),
//    with destructive actions styled in the error colour.
//  - screen-reader custom actions mirroring the sheet, so every action stays
//    reachable without gestures (TalkBack/VoiceOver users can't discover swipes).
//
// The first swipe reveals a coloured, labelled background, which is what
// teaches the gesture — there is no visible affordance on the card itself.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

/// One contextual action on a list row.
class RowAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Destructive actions (delete) render in the error colour in the sheet and
  /// must never be passed as a swipe action.
  final bool destructive;

  const RowAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

class RowActions extends StatelessWidget {
  /// Stable row identity (usually the entity id) — keys the swipe state.
  final Object id;

  final Widget child;

  /// Triggered by a left-to-right swipe. Keep it the row's primary safe action.
  final RowAction? swipeStart;

  /// Triggered by a right-to-left swipe.
  final RowAction? swipeEnd;

  /// Full action list for the long-press sheet. Usually includes the swipe
  /// actions too, so everything is discoverable in one place.
  final List<RowAction> menu;

  /// Sheet header — typically the row's title, so it's clear what's acted on.
  final String? title;

  RowActions({
    super.key,
    required this.id,
    required this.child,
    this.swipeStart,
    this.swipeEnd,
    this.menu = const [],
    this.title,
  })  : assert(swipeStart == null || !swipeStart.destructive,
            'Destructive actions must not be swipeable'),
        assert(swipeEnd == null || !swipeEnd.destructive,
            'Destructive actions must not be swipeable');

  @override
  Widget build(BuildContext context) {
    Widget result = child;

    if (menu.isNotEmpty) {
      result = GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _openSheet(context);
        },
        child: result,
      );
    }

    final direction = swipeStart != null && swipeEnd != null
        ? DismissDirection.horizontal
        : swipeStart != null
            ? DismissDirection.startToEnd
            : swipeEnd != null
                ? DismissDirection.endToStart
                : null;

    if (direction != null) {
      result = Dismissible(
        key: ValueKey('row-actions-$id'),
        direction: direction,
        dismissThresholds: const {
          DismissDirection.startToEnd: 0.35,
          DismissDirection.endToStart: 0.35,
        },
        // Trigger the action and spring back — the row is never dismissed.
        confirmDismiss: (d) async {
          HapticFeedback.mediumImpact();
          final action = d == DismissDirection.startToEnd
              ? (swipeStart ?? swipeEnd)
              : (swipeEnd ?? swipeStart);
          action?.onTap();
          return false;
        },
        background: _swipeBackground(
          context,
          swipeStart ?? swipeEnd!,
          alignStart: swipeStart != null,
        ),
        secondaryBackground: swipeStart != null && swipeEnd != null
            ? _swipeBackground(context, swipeEnd!, alignStart: false)
            : null,
        child: result,
      );
    }

    if (menu.isNotEmpty) {
      result = Semantics(
        customSemanticsActions: {
          for (final a in menu) CustomSemanticsAction(label: a.label): a.onTap,
        },
        child: result,
      );
    }
    return result;
  }

  Widget _swipeBackground(BuildContext context, RowAction action,
      {required bool alignStart}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(action.icon, size: 20, color: cs.onPrimaryContainer),
          const SizedBox(width: 8),
          Text(
            action.label,
            style: TextStyle(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _openSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      // A row can offer seven actions (a due does). Without this the sheet is
      // capped at 9/16 of the screen and the last ones are clipped off the
      // bottom, unreachable; the scroll view keeps a long menu usable while a
      // short one still sizes to its content.
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
              for (final a in menu)
                ListTile(
                  leading: Icon(a.icon, color: a.destructive ? cs.error : null),
                  title: Text(a.label,
                      style: a.destructive ? TextStyle(color: cs.error) : null),
                  onTap: () {
                    Navigator.pop(ctx);
                    a.onTap();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
