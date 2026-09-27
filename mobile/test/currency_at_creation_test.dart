// A workspace's currency is chosen by the person when it is created, and can
// never be changed afterwards. These pin down each step of that: what gets
// preselected, how the picker finds a currency, what is written, and that a
// first sign-in cannot reach the app without making the choice.
//
// Everything runs at a 360dp phone width, where this app has overflowed
// before in ways an 800px test surface hides.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/core/theme.dart';
import 'package:nizkhata/router.dart';
import 'package:nizkhata/screens/choose_currency_screen.dart';
import 'package:nizkhata/screens/profile_screen.dart';
import 'package:nizkhata/state/auth_controller.dart';
import 'package:nizkhata/widgets/currency_picker.dart';

void phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget app(Widget home) => MaterialApp(theme: buildLightTheme(), home: home);

void main() {
  group('the preselected currency', () {
    test('follows the phone region when there is a currency for it', () {
      expect(suggestedCurrency(const Locale('en', 'IN')), 'INR');
      expect(suggestedCurrency(const Locale('en', 'US')), 'USD');
      expect(suggestedCurrency(const Locale('ar', 'AE')), 'AED');
      expect(suggestedCurrency(const Locale('de', 'DE')), 'EUR');
    });

    test('is the rupee when the phone gives nothing to go on', () {
      expect(suggestedCurrency(null), 'INR');
      expect(suggestedCurrency(const Locale('en')), 'INR');
      expect(suggestedCurrency(const Locale('en', 'ZZ')), 'INR');
    });
  });

  group('the workspace that gets written', () {
    test('keeps its books in the chosen currency, with that currency\'s usual year', () {
      final usd = newWorkspaceFields(id: 'w1', name: 'Home', ownerId: 'u1', currency: 'USD');
      expect(usd['baseCurrency'], 'USD');
      expect(usd['fyStartMonth'], 1);
      expect(usd['id'], 'w1');
      expect(usd['name'], 'Home');
      expect(usd['ownerId'], 'u1');

      final aud = newWorkspaceFields(id: 'w', name: 'n', ownerId: 'u', currency: 'AUD');
      expect(aud['baseCurrency'], 'AUD');
      expect(aud['fyStartMonth'], 7);

      final inr = newWorkspaceFields(id: 'w', name: 'n', ownerId: 'u', currency: 'INR');
      expect(inr['baseCurrency'], 'INR');
      expect(inr['fyStartMonth'], 4);
    });

    test('stores the code in its standard form', () {
      final gbp = newWorkspaceFields(id: 'w', name: 'n', ownerId: 'u', currency: ' gbp ');
      expect(gbp['baseCurrency'], 'GBP');
      expect(gbp['fyStartMonth'], 4);
    });

    test('refuses a code the app does not offer rather than store it for good', () {
      expect(
        () => newWorkspaceFields(id: 'w', name: 'n', ownerId: 'u', currency: 'XYZ'),
        throwsArgumentError,
      );
    });

    test('is named after the person when they have not named it', () {
      expect(defaultWorkspaceName('Asha Rao'), "Asha's Workspace");
      expect(defaultWorkspaceName(null), 'My Workspace');
      expect(defaultWorkspaceName('  '), 'My Workspace');
    });
  });

  group('the first-run gate', () {
    String? go(String loc, {bool needsWorkspace = false, bool signedIn = true, bool loading = false}) =>
        authRedirect(loc, loading: loading, signedIn: signedIn, needsWorkspace: needsWorkspace);

    test('holds someone with no workspace on the currency screen, wherever they were headed', () {
      expect(go('/dashboard', needsWorkspace: true), '/welcome');
      expect(go('/login', needsWorkspace: true), '/welcome');
      expect(go('/txns', needsWorkspace: true), '/welcome');
      expect(go('/welcome', needsWorkspace: true), isNull);
    });

    test('lets them into the app once the workspace exists', () {
      expect(go('/welcome'), '/dashboard');
    });

    test('changes nothing for someone who already has a workspace', () {
      expect(go('/dashboard'), isNull);
      expect(go('/txns'), isNull);
      expect(go('/login'), '/dashboard');
      expect(go('/settings/accounts'), '/accounts');
    });

    test('still sends a signed-out person to sign in', () {
      expect(go('/welcome', signedIn: false), '/login');
      expect(go('/login', signedIn: false), isNull);
      expect(go('/welcome', loading: true, signedIn: false), isNull);
    });
  });

  group('the currency picker', () {
    Future<List<String?>> openPicker(WidgetTester tester, {String? selected}) async {
      final results = <String?>[];
      phoneSize(tester);
      await tester.pumpWidget(app(Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => results.add(await showCurrencyPicker(context, selected: selected)),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('lists each currency with its code, name and symbol', (tester) async {
      await openPicker(tester, selected: 'INR');
      expect(find.text('Choose currency'), findsOneWidget);
      final inr = find.byKey(const ValueKey('currency-INR'));
      expect(find.descendant(of: inr, matching: find.text('Indian rupee')), findsOneWidget);
      expect(find.descendant(of: inr, matching: find.text('INR')), findsOneWidget);
      expect(find.descendant(of: inr, matching: find.text('₹')), findsOneWidget);
      // The current choice is marked.
      expect(find.descendant(of: inr, matching: find.byIcon(Icons.check)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('finds currencies by name', (tester) async {
      await openPicker(tester);
      await tester.enterText(find.byType(TextField), 'dollar');
      await tester.pumpAndSettle();
      expect(find.text('US dollar'), findsOneWidget);
      expect(find.text('Singapore dollar'), findsOneWidget);
      expect(find.text('Indian rupee'), findsNothing);
      expect(find.text('Euro'), findsNothing);
    });

    testWidgets('finds a currency by its code, in either case', (tester) async {
      await openPicker(tester);
      await tester.enterText(find.byType(TextField), 'aed');
      await tester.pumpAndSettle();
      expect(find.text('UAE dirham'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await openPicker(tester);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('No currency matches "zzz".'), findsOneWidget);
    });

    testWidgets('hands back the code that was tapped', (tester) async {
      final results = await openPicker(tester);
      await tester.enterText(find.byType(TextField), 'AED');
      await tester.pumpAndSettle();
      await tester.tap(find.text('UAE dirham'));
      await tester.pumpAndSettle();
      expect(results, ['AED']);
      expect(find.text('Choose currency'), findsNothing);
    });

    test('filters without a widget too', () {
      expect(filterCurrencies('').length, greaterThan(30));
      expect(filterCurrencies('AED').map((c) => c.code), ['AED']);
      expect(filterCurrencies('rupee').map((c) => c.code), containsAll(['INR', 'PKR', 'NPR', 'LKR']));
      expect(filterCurrencies('£').map((c) => c.code), ['GBP']);
    });
  });

  group('the first-run screen', () {
    Future<List<String>> pumpScreen(
      WidgetTester tester, {
      String initial = 'USD',
      Future<void> Function(String)? onConfirm,
    }) async {
      final confirmed = <String>[];
      phoneSize(tester);
      await tester.pumpWidget(app(ChooseCurrencyView(
        firstName: 'Asha',
        initialCurrency: initial,
        onConfirm: onConfirm ?? (c) async => confirmed.add(c),
        onSignOut: () async {},
      )));
      await tester.pumpAndSettle();
      return confirmed;
    }

    testWidgets('preselects the suggestion and says the choice is for good', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Welcome, Asha'), findsOneWidget);
      expect(find.text('US dollar'), findsOneWidget);
      expect(find.textContaining("can't be changed later"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('creates nothing until the person confirms, then uses their choice', (tester) async {
      final confirmed = await pumpScreen(tester);
      expect(confirmed, isEmpty);

      await tester.tap(find.text('US dollar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'euro');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Euro'));
      await tester.pumpAndSettle();
      expect(find.text('EUR'), findsOneWidget);

      await tester.tap(find.text('Create my workspace'));
      await tester.pump();
      expect(confirmed, ['EUR']);
    });

    testWidgets('keeps the person on the screen, able to retry, when creation fails', (tester) async {
      var attempts = 0;
      await pumpScreen(tester, onConfirm: (_) async {
        attempts++;
        throw Exception('offline');
      });
      await tester.tap(find.text('Create my workspace'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.textContaining("Couldn't set up your workspace"), findsOneWidget);

      await tester.tap(find.text('Create my workspace'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
    });
  });

  group('the new-workspace dialog', () {
    Future<List<NewWorkspaceRequest?>> pumpDialog(WidgetTester tester, {required String initial}) async {
      final results = <NewWorkspaceRequest?>[];
      phoneSize(tester);
      await tester.pumpWidget(app(Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => results.add(await showDialog<NewWorkspaceRequest>(
                context: context,
                builder: (_) => NewWorkspaceDialog(initialCurrency: initial),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    FilledButton createButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'));

    testWidgets('starts from the current workspace\'s currency and returns the choice', (tester) async {
      final results = await pumpDialog(tester, initial: 'AED');
      expect(find.text('UAE dirham'), findsOneWidget);
      expect(find.textContaining("can't be changed later"), findsOneWidget);
      expect(tester.takeException(), isNull);

      // No name, no workspace.
      expect(createButton(tester).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '  Household ');
      await tester.pump();
      expect(createButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(results.single?.name, 'Household');
      expect(results.single?.currency, 'AED');
    });

    testWidgets('lets the currency be changed before creating', (tester) async {
      final results = await pumpDialog(tester, initial: 'INR');
      await tester.enterText(find.byType(TextField), 'Travel');
      await tester.tap(find.text('Indian rupee'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'JPY');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Japanese yen'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(results.single, (name: 'Travel', currency: 'JPY'));
    });

    testWidgets('fits a phone with the keyboard up', (tester) async {
      await pumpDialog(tester, initial: 'KWD');
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('starts from the rupee when the current code is not one the app offers', (tester) async {
      await pumpDialog(tester, initial: 'XYZ');
      expect(find.text('Indian rupee'), findsOneWidget);
    });

    testWidgets('cancelling returns nothing', (tester) async {
      final results = await pumpDialog(tester, initial: 'INR');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });
  });
}
