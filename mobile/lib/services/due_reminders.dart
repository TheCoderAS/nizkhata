// Push notifications shown by the app: due reminders and shared ledger news.
//
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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:ui' show Color;

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

  /// Shared ledger news (an entry added, accepted or rejected), apart from
  /// reminders so either can be muted without the other.
  static const _sharedChannel = AndroidNotificationChannel(
    'shared_ledger',
    'Shared ledger',
    description: 'When someone adds, accepts or rejects an entry you share',
    importance: Importance.high,
  );

  /// Reminders used to be scheduled on the phone; this marks them cleared.
  static const _clearedKey = 'localRemindersCleared';

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      // The white Niz Khata silhouette: Android draws status-bar icons as a mask.
      const androidInit = AndroidInitializationSettings('ic_stat_due');
      await _plugin.initialize(
        const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: (resp) => _open(resp.payload),
      );
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_channel);
      await android?.createNotificationChannel(_sharedChannel);
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
    // Never someone's reminder on a phone nobody is signed in to.
    if (FirebaseAuth.instance.currentUser == null) return;
    final route = (m.data['route'] as String?) ?? '';
    final channel = n.android?.channelId == _sharedChannel.id ? _sharedChannel : _channel;
    await _plugin.show(
      // Reminders: one per day, replaced by the next slot's, like the
      // backend's tag. Shared ledger: one per entry, each its own.
      route.hashCode & 0x7fffffff,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: 'ic_stat_due',
          color: const Color(0xFF4F46E5),
          importance: Importance.high,
          priority: Priority.high,
          category: channel == _channel ? AndroidNotificationCategory.reminder : AndroidNotificationCategory.social,
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
