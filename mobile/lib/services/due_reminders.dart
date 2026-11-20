// Due reminders: "You have N dues to clear today", at 9:00, 12:00, 15:00,
// 18:00 and 21:00 on a day with unsettled dues. They are push notifications
// from the Niz Khata backend (see push_registration.dart), so they arrive
// whether or not the app has been opened, and nothing is scheduled here.
//
// What is left on the phone: the notification channel the pushes are shown
// in, showing one while the app is in front (Android leaves that to the app),
// opening the Dues screen for that day when one is tapped, and, once after
// updating, clearing the reminders older versions scheduled on the phone so
// nobody gets each one twice.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DueReminders {
  DueReminders._();
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Set by main.dart: receives the route (e.g. /dues-day?date=...) when a
  /// reminder is tapped.
  static void Function(String route)? onOpenRoute;

  static bool _inited = false;
  static String? _pendingRoute;

  static const _channel = AndroidNotificationChannel(
    'due_reminders',
    'Due reminders',
    description: 'Reminders on the day a due is to be cleared',
    importance: Importance.high,
  );

  /// Reminders used to be scheduled on the phone; this marks them cleared.
  static const _clearedKey = 'localRemindersCleared';

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: (resp) => _open(resp.payload),
      );
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_channel);
      await android?.requestNotificationsPermission();

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_clearedKey) != true) {
        await _plugin.cancelAll();
        await prefs.setBool(_clearedKey, true);
      }

      // A reminder shown while the app is open.
      FirebaseMessaging.onMessage.listen(_showForeground);
      // A reminder tapped while the app was in the background...
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data['route'] as String?));
      // ...or one that started the app: a push, or one shown by [_showForeground].
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      final route = initial?.data['route'] as String?;
      if (route != null && route.isNotEmpty) _pendingRoute = route;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if ((launch?.didNotificationLaunchApp ?? false) && payload != null && payload.isNotEmpty) {
        _pendingRoute = payload;
      }
    } catch (e) {
      debugPrint('DueReminders.init failed: $e');
    }
  }

  static void _open(String? route) {
    if (route == null || route.isEmpty) return;
    final open = onOpenRoute;
    if (open != null) {
      open(route);
    } else {
      _pendingRoute = route;
    }
  }

  static Future<void> _showForeground(RemoteMessage m) async {
    final n = m.notification;
    if (n == null) return;
    final date = (m.data['route'] as String?) ?? '';
    await _plugin.show(
      // One per day, replaced by the next slot's, like the backend's tag.
      date.hashCode & 0x7fffffff,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
      payload: m.data['route'] as String?,
    );
  }

  /// Remove every reminder this app has on screen.
  static Future<void> clear() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Route waiting from a tap that happened before the router was ready.
  static String? takePendingRoute() {
    final r = _pendingRoute;
    _pendingRoute = null;
    return r;
  }
}
