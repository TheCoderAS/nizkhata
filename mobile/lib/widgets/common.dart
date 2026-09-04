// Shared UI atoms — ports of StatCard, EntityAvatar, and simple state views.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../core/format.dart';
import '../core/theme.dart';

enum StatTone { neutral, success, danger }

class StatCard extends StatelessWidget {
  final String label;
  final double amount;
  final String currency;
  final String? hint;
  final IconData? icon;
  final StatTone tone;

  /// Optional inline chart (e.g. a sparkline) rendered INSIDE the card, below
  /// the value — so trend graphs sit within the card, not floating beneath it.
  final Widget? chart;
  const StatCard({
    super.key,
    required this.label,
    required this.amount,
    required this.currency,
    this.hint,
    this.icon,
    this.tone = StatTone.neutral,
    this.chart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color valueColor;
    Color iconBg;
    Color iconFg;
    switch (tone) {
      case StatTone.success:
        valueColor = AppColors.accent2;
        iconBg = AppColors.accent2.withValues(alpha: 0.12);
        iconFg = AppColors.accent2;
        break;
      case StatTone.danger:
        valueColor = AppColors.danger;
        iconBg = AppColors.danger.withValues(alpha: 0.12);
        iconFg = AppColors.danger;
        break;
      case StatTone.neutral:
        valueColor = cs.onSurface;
        iconBg = cs.primary.withValues(alpha: 0.12);
        iconFg = cs.primary;
        break;
    }
    return Card(
      child: DecoratedBox(
        // A whisper of the card's own tone, strongest at the top-left corner
        // and gone by the opposite one, so the number is framed by colour
        // instead of sitting on flat grey.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [iconFg.withValues(alpha: 0.10), iconFg.withValues(alpha: 0.0)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ),
                  if (icon != null)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(9)),
                      child: Icon(icon, size: 16, color: iconFg),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatMoneyCompact(amount, currency),
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: valueColor),
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(hint!, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
              if (chart != null) ...[
                const SizedBox(height: 10),
                SizedBox(height: 30, child: chart),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EntityAvatar extends StatelessWidget {
  final String name;
  final double size;
  const EntityAvatar({super.key, required this.name, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final g = avatarGradient(name.isEmpty ? '?' : name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [g.from, g.to],
        ),
      ),
      child: Text(
        initialsOf(name),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.34),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;
  const SectionCard({super.key, required this.title, required this.child, this.trailing, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 17, color: cs.primary),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
}

class EmptyView extends StatelessWidget {
  final String title;
  final String? hint;
  final Widget? action;
  final IconData icon;
  const EmptyView({super.key, required this.title, this.hint, this.action, this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withValues(alpha: 0.20),
                    cs.tertiary.withValues(alpha: 0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Icon(icon, size: 30, color: cs.primary),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(hint!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Shimmering skeleton block for loading placeholders.
class Skeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? radius;
  const Skeleton({super.key, this.width = double.infinity, this.height = 14, this.radius});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.radius ?? BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * t, 0),
              end: Alignment(1 - 2 * t, 0),
              colors: [
                cs.surfaceContainerHighest.withValues(alpha: 0.4),
                cs.surfaceContainerHighest.withValues(alpha: 0.8),
                cs.surfaceContainerHighest.withValues(alpha: 0.4),
              ],
              stops: const [0.1, 0.5, 0.9],
            ),
          ),
        );
      },
    );
  }
}

/// A list of shimmer rows — a nicer loading state than a bare spinner.
class ListSkeleton extends StatelessWidget {
  final int rows;
  const ListSkeleton({super.key, this.rows = 7});
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, __) => Row(
        children: const [
          Skeleton(width: 40, height: 40, radius: null),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 160, height: 13),
                SizedBox(height: 8),
                Skeleton(width: 90, height: 11),
              ],
            ),
          ),
          SizedBox(width: 12),
          Skeleton(width: 56, height: 13),
        ],
      ),
    );
  }
}

// ---- shared screen atoms ---------------------------------------------------
// These existed as private copies in five or six screens that had quietly
// drifted apart (different label spacing, one detail sheet laying its rows out
// side-by-side while the rest used a label column, a search field with a clear
// button on one screen only). One definition each, so a component looks the
// same wherever it turns up.

/// Small caps heading above a group of fields in a form sheet.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

/// One "label: value" line in a read-only detail sheet. The label sits in a
/// fixed column so values line up down the sheet.
class DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const DetailRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: TextStyle(color: cs.onSurfaceVariant))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// An active filter, shown as a chip you can dismiss to clear that filter.
class RemovableChip extends StatelessWidget {
  final String label;
  final VoidCallback onClear;
  const RemovableChip(this.label, this.onClear, {super.key});

  @override
  Widget build(BuildContext context) => InputChip(
        label: Text(label),
        onDeleted: onClear,
        deleteIcon: const Icon(Icons.close, size: 16),
      );
}

/// The search box at the top of a list screen. Always offers a clear button
/// once there is something to clear.
class SearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  /// Supply one only when the screen needs to clear or seed the box itself.
  final TextEditingController? controller;

  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  TextEditingController? _own;
  TextEditingController get _controller => widget.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (v) {
        widget.onChanged(v);
        setState(() {}); // reveal/hide the clear button
      },
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        isDense: true,
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
      ),
    );
  }
}

/// The app's action button. Same fill as a Material small FAB
/// (primaryContainer), so the big button and the little ones that fan out of
/// it on the transactions screen read as one family instead of two.
class AppFab extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;

  /// Overrides [icon] — for buttons whose glyph animates (the transactions
  /// FAB rotates its plus into a close).
  final Widget? child;
  const AppFab({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.icon = Icons.add,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Steps aside while you scroll down a list, so it stops covering the
    // figure in the row beneath it. Scale rather than opacity: a half-faded
    // button still takes the tap.
    final visible = FabVisibility.of(context);
    // MergeSemantics: without it the InkWell publishes its own unlabelled
    // button node beside this one, and a screen reader reads an anonymous
    // button.
    return AnimatedScale(
      scale: visible ? 1 : 0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: MergeSemantics(
        child: Tooltip(
          message: tooltip,
          child: Semantics(
            button: true,
            label: tooltip,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onPressed,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: IconTheme(
                      data: IconThemeData(color: cs.onPrimaryContainer, size: 26),
                      child: child ?? Icon(icon),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and lifts a list card into place. Subtle on purpose: enough to make a
/// list feel built rather than dumped, not enough to notice twice.
class EntranceFade extends StatelessWidget {
  final Widget child;

  /// Position in the list, used to stagger the first few rows.
  final int index;
  const EntranceFade({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (index.clamp(0, 6) * 25)),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: child,
    );
  }
}

/// An amount that carries its own direction, so nothing has to say it in words.
///
/// Money coming in reads plainly and green; money going out is parenthesised
/// and red, which is how a ledger has always written a negative. The arrow is
/// not decoration: colour alone fails a colour-blind reader and dies in a
/// greyscale screenshot, so the direction survives without it.
///
/// The words are still there for anyone who cannot see either — they live in
/// the semantics label, which is where text belongs once a symbol has done the
/// job on screen.
class SignedAmount extends StatelessWidget {
  /// Always the magnitude. [inbound] decides how it reads.
  final double amount;

  /// True for a receivable: money owed TO you.
  final bool inbound;
  final String currency;
  final double fontSize;
  final FontWeight fontWeight;

  const SignedAmount({
    super.key,
    required this.amount,
    required this.inbound,
    required this.currency,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w600,
  });

  @override
  Widget build(BuildContext context) {
    // A debt that has been paid off is neither a receivable nor a payable any
    // more. Pointing an arrow at nothing, in the colour of money still owed,
    // says the opposite of what a settled row means.
    if (amount.abs() <= 0.005) {
      final cs = Theme.of(context).colorScheme;
      return Semantics(
        label: 'Settled',
        child: ExcludeSemantics(
          child: Text(
            formatMoney(0, currency),
            style: TextStyle(fontSize: fontSize, fontWeight: fontWeight, color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    final tone = inbound ? AppColors.accent2 : AppColors.danger;
    // formatMoney parenthesises a negative, which is the whole convention.
    final text = formatMoney(inbound ? amount.abs() : -amount.abs(), currency);
    return Semantics(
      label: '${inbound ? 'Receivable' : 'Payable'} ${formatMoney(amount.abs(), currency)}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(inbound ? Icons.south_west : Icons.north_east, size: fontSize, color: tone),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(fontSize: fontSize, fontWeight: fontWeight, color: tone),
            ),
          ],
        ),
      ),
    );
  }
}

/// A choice in a picker, marked with the same arrow the lists use so the two
/// read as one system: pick "Payable" here and the amount shows up red with an
/// outbound arrow everywhere afterwards.
class DirectionOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const DirectionOption({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      );
}

/// Whether the floating action button should currently be showing.
///
/// A FAB parked in the bottom-right corner sits exactly where a list puts its
/// amounts, so on a screen of figures it permanently hides one of them. Rather
/// than move the button or give up the corner, it gets out of the way while you
/// are scrolling down through the list and comes back the moment you stop or
/// scroll up.
///
/// It lives above the shell's body so one listener covers every tab, and every
/// screen's AppFab reads it without knowing any of this.
class FabVisibility extends InheritedNotifier<ValueNotifier<bool>> {
  const FabVisibility({super.key, required ValueNotifier<bool> super.notifier, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FabVisibility>()?.notifier?.value ?? true;
}

/// Watches the body's scrolling and drives a [FabVisibility] from it.
class FabScrollScope extends StatefulWidget {
  final Widget child;
  const FabScrollScope({super.key, required this.child});

  @override
  State<FabScrollScope> createState() => _FabScrollScopeState();
}

class _FabScrollScopeState extends State<FabScrollScope> {
  final _visible = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _visible.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    // Only the body's own vertical list. A horizontal strip of chips, or a
    // list inside a sheet on top of it, is not what this is about.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    // Hide while the list is being pulled up, come back the moment it is
    // pulled down again. Coming back on `idle` instead would pop the button
    // out the instant a finger lifts, while a fling is still running.
    if (n is UserScrollNotification) {
      if (n.direction == ScrollDirection.reverse) _visible.value = false;
      if (n.direction == ScrollDirection.forward) _visible.value = true;
    } else if (n is ScrollEndNotification) {
      _visible.value = true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: FabVisibility(notifier: _visible, child: widget.child),
      );
}
