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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
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
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: cs.onSurfaceVariant),
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
