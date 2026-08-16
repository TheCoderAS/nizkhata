// Due reminders — a single aggregated local notification per time slot on each
// day that has unsettled dues ("You have N dues to clear today"), fired by
// Android's AlarmManager so it works even when the app is closed. Tapping opens
// the Dues screen filtered to that day (/dues-day?date=…). Schedules are
// recomputed from the live dues list on every app open and dues change, and are
// re-registered after reboot by the plugin's boot receiver.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/derive.dart';
import '../data/models.dart';

class DueReminders {
  DueReminders._();
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Set by main.dart — receives the payload route (e.g. /dues-day?date=…)
  /// when a notification is tapped.
  static void Function(String route)? onOpenRoute;

  static bool _inited = false;
  static String? _pendingRoute;

  /// Reminder slots on the due day (hours, local time). 09:00–21:00 every 3h —
  /// deliberately not a 24h grid so nobody gets buzzed at 3am.
  static const _slots = [9, 12, 15, 18, 21];

  /// How many days ahead to keep scheduled (well under Android's ~500 cap:
  /// 30 days × 5 slots = 150 worst case).
  static const _horizonDays = 30;

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Keep the default (UTC) — reminders still fire, at shifted hours.
    }
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (resp) {
        final p = resp.payload;
        if (p != null && p.isNotEmpty) {
          final open = onOpenRoute;
          if (open != null) {
            open(p);
          } else {
            _pendingRoute = p;
          }
        }
      },
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    // Cold start from a notification tap: stash the route until the router is up.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) && payload != null && payload.isNotEmpty) {
      _pendingRoute = payload;
    }
  }

  /// Route waiting from a tap that happened before the router was ready.
  static String? takePendingRoute() {
    final r = _pendingRoute;
    _pendingRoute = null;
    return r;
  }

  /// Recompute the whole schedule from the current dues. One aggregated
  /// notification per slot per day that has unsettled dues due that day.
  static Future<void> sync(List<Due> dues, double Function(String dueId) settledOf) async {
    if (!_inited) return;
    try {
      await _plugin.cancelAll();

      // Count unsettled dues per due-date (today .. horizon).
      final now = tz.TZDateTime.now(tz.local);
      final today = DateTime(now.year, now.month, now.day);
      final counts = <DateTime, int>{};
      for (final d in dues) {
        final st = dueStatusFromSettled(d, settledOf(d.id));
        if (st != 'open' && st != 'partial') continue;
        final day = DateTime(d.dueDate.year, d.dueDate.month, d.dueDate.day);
        if (day.isBefore(today)) continue;
        if (day.difference(today).inDays > _horizonDays) continue;
        counts[day] = (counts[day] ?? 0) + 1;
      }

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'due_reminders',
          'Due reminders',
          channelDescription: 'Reminders on the day a due is to be cleared',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
      );

      for (final e in counts.entries) {
        final day = e.key;
        final n = e.value;
        final dateStr =
            '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        for (final hour in _slots) {
          final when = tz.TZDateTime(tz.local, day.year, day.month, day.day, hour);
          if (!when.isAfter(now)) continue; // past slots today
          // Stable id per (day, slot) so reschedules replace cleanly.
          final id = ((day.year * 10000 + day.month * 100 + day.day) % 1000000) * 10 + _slots.indexOf(hour);
          await _zonedSchedule(
            id,
            n == 1 ? 'You have a due to clear today' : 'You have $n dues to clear today',
            'Tap to see what\'s due',
            when,
            details,
            payload: '/dues-day?date=$dateStr',
          );
        }
      }
    } catch (e) {
      debugPrint('DueReminders.sync failed: $e');
    }
  }

  /// Exact when permitted; falls back to inexact (fires within a small window).
  static Future<void> _zonedSchedule(
    int id,
    String title,
    String body,
    tz.TZDateTime when,
    NotificationDetails details, {
    required String payload,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    }
  }
}
