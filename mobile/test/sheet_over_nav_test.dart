import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app puts its tab screens inside a ShellRoute, which builds a nested
/// Navigator inside the Scaffold body. A sheet opened without
/// `useRootNavigator` lands on THAT navigator, so it is confined to the body:
/// the nav bar stays lit below it and — the part that matters — outside the
/// modal barrier, so its tabs still take taps while a modal is open.
///
/// This harness mirrors that arrangement exactly.
void main() {
  Future<int> pumpShell(WidgetTester tester, {required bool useRoot}) async {
    var navTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: SizedBox(
          height: 70,
          child: Center(
            child: TextButton(
              onPressed: () => navTaps++,
              child: const Text('Debts tab'),
            ),
          ),
        ),
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (inner) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: inner,
                  useRootNavigator: useRoot,
                  builder: (_) => const SizedBox(
                    height: 260,
                    child: Center(child: Text('sheet')),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);

    // Try to change tabs while the modal is up.
    await tester.tap(find.text('Debts tab'), warnIfMissed: false);
    await tester.pumpAndSettle();
    return navTaps;
  }

  testWidgets('a sheet on the nested navigator leaves the nav bar live',
      (tester) async {
    // Characterisation of the bug: the tab still fires, so you can navigate
    // underneath an open modal.
    expect(await pumpShell(tester, useRoot: false), 1);
  });

  testWidgets('a sheet on the root navigator covers the nav bar',
      (tester) async {
    expect(await pumpShell(tester, useRoot: true), 0,
        reason: 'the modal barrier should swallow taps on the nav bar');
  });
}
