// Shared UI atoms — ports of StatCard, EntityAvatar, and simple state views.

import 'package:flutter/material.dart';

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
                      decoration:
                          BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(9)),
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
  const SectionCard(
      {super.key, required this.title, required this.child, this.trailing, this.icon});

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
  const EmptyView(
      {super.key, required this.title, this.hint, this.action, this.icon = Icons.inbox_outlined});
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
              Text(hint!,
                  textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
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
    // MergeSemantics: without it the InkWell publishes its own unlabelled
    // button node beside this one, and a screen reader reads an anonymous
    // button.
    return MergeSemantics(
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
