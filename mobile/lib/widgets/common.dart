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
  const StatCard({
    super.key,
    required this.label,
    required this.amount,
    required this.currency,
    this.hint,
    this.icon,
    this.tone = StatTone.neutral,
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
            Text(
              formatMoney(amount, currency),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: valueColor),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint!, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
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
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
  const EmptyView({super.key, required this.title, this.hint, this.action});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(hint!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
