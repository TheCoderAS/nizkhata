// Push notifications. Due reminders are sent by the Niz Khata backend, which
// also creates repeating dues and card bills on schedule, so nothing on this
// phone has to wake up to do them.
//
// The phone's part is to say where to send them: on sign-in it records this
// install's push token, time zone and date locale in `devices/{uid}_{install}`
// (the time zone is what makes a 9:00 reminder arrive at 9:00 here), keeps the
// token fresh, and removes the record on sign-out and account deletion.

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/format.dart';

class PushRegistration {
  PushRegistration._();

  static const _installKey = 'pushInstallId';
  static String? _uid;
  static StreamSubscription<String>? _refresh;

  /// This install's id: random, kept on the phone, so each phone a person
  /// signs in on is its own device record.
  static Future<String> _installId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_installKey);
    if (id == null || id.isEmpty) {
      const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final r = Random.secure();
      id = List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
      await prefs.setString(_installKey, id);
    }
    return id;
  }

  static Future<DocumentReference<Map<String, dynamic>>> _doc(String uid) async =>
      FirebaseFirestore.instance.collection('devices').doc('${uid}_${await _installId()}');

  /// Call whenever the signed-in user changes (null when signed out).
  static Future<void> sync(String? uid) async {
    if (uid == _uid) return;
    _uid = uid;
    await _refresh?.cancel();
    _refresh = null;
    if (uid == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) await _write(uid, token);
      _refresh = messaging.onTokenRefresh.listen((t) {
        if (_uid == uid) _write(uid, t).catchError((Object e) => debugPrint('push token refresh: $e'));
      });
    } catch (e) {
      // No Play services, or offline: reminders simply don't arrive on this
      // phone until the next sign-in or app start manages it.
      debugPrint('push registration failed: $e');
    }
  }

  static Future<void> _write(String uid, String token) async {
    String timeZone = '';
    try {
      timeZone = await FlutterTimezone.getLocalTimezone();
    } catch (_) {}
    await (await _doc(uid)).set({
      'uid': uid,
      'token': token,
      'timeZone': timeZone,
      'locale': AppLocale.date,
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stop reminders to this phone. Call BEFORE signing out, while the record
  /// can still be deleted as its owner.
  static Future<void> unregister() async {
    final uid = _uid;
    _uid = null;
    await _refresh?.cancel();
    _refresh = null;
    if (uid == null) return;
    try {
      await (await _doc(uid)).delete();
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('push unregister failed: $e');
    }
  }
}
