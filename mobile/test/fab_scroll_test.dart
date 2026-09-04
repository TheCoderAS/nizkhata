// The action button sits in the bottom-right corner, which is exactly where a
// list of money puts its figures. It has to get out of the way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/core/theme.dart';
import 'package:nizkhata/widgets/common.dart';

void main() {
  /// The shell's arrangement: one scope over a body that scrolls, with the
  /// action button in the Scaffold's own slot beside it, not inside the list.
  Future<void> pumpShell(WidgetTester tester, {ScrollController? controller}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: FabScrollScope(
        child: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: 60,
            itemBuilder: (_, i) => SizedBox(height: 80, child: Text('row $i')),
          ),
          floatingActionButton: AppFab(onPressed: () {}, tooltip: 'Add debt'),
        ),
      ),
    ));
  }

  double scaleOf(WidgetTester tester) => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('is there to begin with', (tester) async {
    await pumpShell(tester);
    expect(scaleOf(tester), 1);
  });

  testWidgets('steps aside while you scroll down the list', (tester) async {
    await pumpShell(tester);
    // Mid-drag, with the finger still down: this is when it is in the way.
    final finger = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await finger.moveBy(const Offset(0, -300));
    await tester.pump();
    expect(scaleOf(tester), 0);
    await finger.up();
  });

  testWidgets('comes back as soon as a slow drag ends', (tester) async {
    await pumpShell(tester);
    final finger = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await finger.moveBy(const Offset(0, -300));
    await tester.pump();
    expect(scaleOf(tester), 0);

    // Lifted without throwing it: the list stops there, so the button returns.
    await finger.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);
  });

  testWidgets('stays away while a fling is still running', (tester) async {
    await pumpShell(tester);
    // Thrown, not dragged: the finger is gone but the list is still moving,
    // and popping the button back over a list in motion is what this avoids.
    await tester.fling(find.byType(ListView), const Offset(0, -400), 3000);
    await tester.pump();
    expect(scaleOf(tester), 0);

    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1);
  });

  testWidgets('comes back straight away when you scroll back up', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller: controller);
    controller.jumpTo(1500);
    await tester.pump();

    final finger = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await finger.moveBy(const Offset(0, -200));
    await tester.pump();
    expect(scaleOf(tester), 0);

    // Reversing without lifting: back before the finger leaves the glass.
    await finger.moveBy(const Offset(0, 200));
    await tester.pump();
    expect(scaleOf(tester), 1);
    await finger.up();
    await tester.pumpAndSettle();
  });

  testWidgets('ignores a sideways scroll, which is not the body moving', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: FabScrollScope(
        child: Scaffold(
          body: SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [for (var i = 0; i < 40; i++) SizedBox(width: 90, child: Text('chip $i'))],
            ),
          ),
          floatingActionButton: AppFab(onPressed: () {}, tooltip: 'Add debt'),
        ),
      ),
    ));
    final finger = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    await finger.moveBy(const Offset(-300, 0));
    await tester.pump();
    expect(scaleOf(tester), 1);
    await finger.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a button outside any scope is simply always there', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(floatingActionButton: AppFab(onPressed: () {}, tooltip: 'Add')),
    ));
    expect(scaleOf(tester), 1);
  });
}
