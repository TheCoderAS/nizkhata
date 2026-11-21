// Dates in the workspace's time zone, wherever the phone is.
//
// Every date is stored as a UTC instant. A day the person picks ("30 Nov") is
// midnight of that day in the WORKSPACE's time zone, not the phone's; and
// every stored instant is shown as the workspace's wall-clock time. So an
// Indian workspace reads the same on a phone in Bangkok or New York, and a due
// saved abroad lands on the day that was picked.
//
// How: the app keeps working with plain DateTime values whose fields are the
// workspace's wall-clock time. They are converted at the edge only:
// [fromStore] when a stored instant is read, [toStore] when a date is written.
// [now] is the workspace's "now" in the same form, for "today" and the like.
//
// With no workspace selected (and in tests) both conversions are the identity,
// so the app behaves exactly as it did.

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class WsTime {
  WsTime._();

  /// Workspaces made before the time zone was stored keep their books in India time.
  static const defaultZone = 'Asia/Kolkata';

  static bool _dbReady = false;
  static tz.Location? _loc;

  /// The workspace's IANA zone in use, or null when none is set.
  static String? get zone => _loc?.name;

  static void _ensureDb() {
    if (_dbReady) return;
    tzdata.initializeTimeZones();
    _dbReady = true;
  }

  /// Use [zoneName] for every conversion from now on; null turns them off.
  static void use(String? zoneName) {
    if (zoneName == null) {
      _loc = null;
      return;
    }
    _ensureDb();
    try {
      _loc = tz.getLocation(zoneName);
    } catch (_) {
      _loc = tz.getLocation(defaultZone);
    }
  }

  /// Every zone the picker offers, by name.
  static List<String> allZones() {
    _ensureDb();
    final names = tz.timeZoneDatabase.locations.keys.where((n) => n.contains('/') && !n.startsWith('Etc/')).toList()..sort();
    return names;
  }

  /// "UTC+5:30" for [zoneName], now.
  static String offsetLabel(String zoneName) {
    _ensureDb();
    try {
      final t = tz.TZDateTime.now(tz.getLocation(zoneName));
      final m = t.timeZoneOffset.inMinutes;
      final sign = m < 0 ? '-' : '+';
      final h = m.abs() ~/ 60;
      final mm = (m.abs() % 60).toString().padLeft(2, '0');
      return mm == '00' ? 'UTC$sign$h' : 'UTC$sign$h:$mm';
    } catch (_) {
      return '';
    }
  }

  /// A stored instant, as the workspace's wall-clock time.
  static DateTime fromStore(DateTime instant) {
    final l = _loc;
    if (l == null) return instant;
    final t = tz.TZDateTime.from(instant, l);
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second, t.millisecond, t.microsecond);
  }

  /// A workspace wall-clock time (a picked day is its midnight), as the instant to store.
  static DateTime toStore(DateTime wall) {
    final l = _loc;
    if (l == null) return wall;
    return tz.TZDateTime(l, wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second, wall.millisecond, wall.microsecond);
  }

  /// Now, as the workspace's wall-clock time.
  static DateTime now() => fromStore(DateTime.now());
}
