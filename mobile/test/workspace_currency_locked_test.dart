// A workspace's currency is shown in Settings, never offered for change.
//
// Every figure in the books is in that currency; switching it would relabel
// them all without converting any, so the rules refuse the change and the
// screen does not pretend it could be made.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/screens/workspace_settings_screen.dart';

Future<void> pump(WidgetTester tester, String currency) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(body: FixedCurrencyField(currency: currency)),
  ));
}

void main() {
  testWidgets('shows the code, name and symbol, and says it is fixed', (tester) async {
    await pump(tester, 'USD');
    expect(find.text('\$'), findsOneWidget);
    expect(find.text('USD · US dollar'), findsOneWidget);
    expect(find.text('Set when this workspace was created. It cannot be changed.'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('is text, not a control', (tester) async {
    await pump(tester, 'INR');
    expect(find.text('₹'), findsOneWidget);
    expect(find.text('INR · Indian rupee'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('a code no longer in the catalogue still reads sensibly', (tester) async {
    await pump(tester, 'XYZ');
    expect(find.text('XYZ · XYZ'), findsOneWidget);
  });

  test('the settings screen never sends a currency', () {
    final screen = File('lib/screens/workspace_settings_screen.dart').readAsStringSync();
    expect(screen, isNot(contains('baseCurrency')));
    // updateWorkspace has no way to take one.
    final mutations = File('lib/data/mutations.dart').readAsStringSync();
    final sig = RegExp(r'Future<void> updateWorkspace\([^)]*\)').firstMatch(mutations)!.group(0)!;
    expect(sig, isNot(contains('Currency')));
  });
}
