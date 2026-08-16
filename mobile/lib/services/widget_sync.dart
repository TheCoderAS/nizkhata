// Home-screen widget data — pushes a "Dues at a glance" summary (receivable /
// payable outstanding + the next upcoming due) into the native widget whenever
// the dues data changes. The native side (DuesWidgetProvider.kt, injected into
// the CI-generated android/ scaffold from android-extras/) renders it.

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/format.dart';
import '../data/derive.dart';
import '../data/models.dart';

class WidgetSync {
  WidgetSync._();

  static Future<void> sync(
    List<Due> dues,
    double Function(String dueId) settledOf,
    String currency,
  ) async {
    try {
      var receivable = 0.0;
      var payable = 0.0;
      Due? next;
      for (final d in dues) {
        final st = dueStatusFromSettled(d, settledOf(d.id));
        if (st != 'open' && st != 'partial') continue;
        final remaining = d.amount - settledOf(d.id);
        if (remaining <= 0.005) continue;
        if (d.direction == 'receivable') {
          receivable += remaining;
        } else {
          payable += remaining;
        }
        if (next == null || d.dueDate.isBefore(next.dueDate)) next = d;
      }
      await HomeWidget.saveWidgetData<String>(
          'receivable', formatMoneyCompact(receivable, currency));
      await HomeWidget.saveWidgetData<String>(
          'payable', formatMoneyCompact(payable, currency));
      await HomeWidget.saveWidgetData<String>(
        'next_due',
        next == null
            ? 'Nothing due — all clear'
            : '${next.title.isNotEmpty ? next.title : 'Due'} · ${formatDate(next.dueDate)}',
      );
      await HomeWidget.updateWidget(androidName: 'DuesWidgetProvider');
    } catch (e) {
      // Widget not placed / provider missing — never let this break the app.
      debugPrint('WidgetSync failed: $e');
    }
  }
}
