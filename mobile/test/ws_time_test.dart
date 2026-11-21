import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/core/ws_time.dart';

// Dates are the workspace's own: a day picked in an Indian workspace is
// midnight in India, whatever the phone's clock says, and reads back as that
// day. The test runner's clock (usually UTC) stands in for "a phone abroad".
void main() {
  tearDown(() => WsTime.use(null));

  test('with no workspace set, nothing is converted', () {
    final d = DateTime(2026, 11, 30);
    expect(WsTime.toStore(d), d);
    expect(WsTime.fromStore(d), d);
  });

  test('a day picked in an Indian workspace is midnight in India', () {
    WsTime.use('Asia/Kolkata');
    final stored = WsTime.toStore(DateTime(2026, 11, 30));
    expect(stored.toUtc(), DateTime.utc(2026, 11, 29, 18, 30));
    // And reads back as 30 November, 00:00, on any phone.
    final back = WsTime.fromStore(Timestamp.fromDate(stored).toDate());
    expect([back.year, back.month, back.day, back.hour, back.minute], [2026, 11, 30, 0, 0]);
  });

  test('a New York workspace keeps New York days, across a DST change', () {
    WsTime.use('America/New_York');
    expect(WsTime.toStore(DateTime(2026, 7, 1)).toUtc(), DateTime.utc(2026, 7, 1, 4)); // EDT
    expect(WsTime.toStore(DateTime(2026, 12, 1)).toUtc(), DateTime.utc(2026, 12, 1, 5)); // EST
    final back = WsTime.fromStore(DateTime.utc(2026, 12, 1, 5));
    expect([back.month, back.day, back.hour], [12, 1, 0]);
  });

  test('the same instant is a different day in different workspaces', () {
    final instant = DateTime.utc(2026, 11, 30, 20); // 01:30 on 1 Dec in India, 15:00 on 30 Nov in New York
    WsTime.use('Asia/Kolkata');
    expect(WsTime.fromStore(instant).day, 1);
    WsTime.use('America/New_York');
    expect(WsTime.fromStore(instant).day, 30);
  });

  test('an unknown zone falls back to India; the picker lists real zones', () {
    WsTime.use('Mars/Olympus');
    expect(WsTime.zone, 'Asia/Kolkata');
    final zones = WsTime.allZones();
    expect(zones, containsAll(['Asia/Kolkata', 'Asia/Bangkok', 'America/New_York']));
    expect(WsTime.offsetLabel('Asia/Kolkata'), 'UTC+5:30');
  });
}
