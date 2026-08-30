import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nizkhata/core/theme.dart';
import 'package:nizkhata/widgets/floating_nav_bar.dart';
import 'package:nizkhata/widgets/segmented_tabs.dart';

Color? fillOf(WidgetTester tester, String label) {
  final box = tester.widget<AnimatedContainer>(
    find
        .ancestor(of: find.text(label), matching: find.byType(AnimatedContainer))
        .first,
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  group('FloatingNavBar', () {
    const items = [
      FloatingNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
      FloatingNavItem(icon: Icons.swap_horiz, selectedIcon: Icons.swap_horiz, label: 'Txns'),
      FloatingNavItem(icon: Icons.receipt_long, selectedIcon: Icons.receipt_long, label: 'Dues'),
      FloatingNavItem(icon: Icons.handshake, selectedIcon: Icons.handshake, label: 'Debts'),
      FloatingNavItem(icon: Icons.menu, selectedIcon: Icons.menu, label: 'More'),
    ];

    Future<int?> pumpBar(WidgetTester tester, {int selected = 0}) async {
      int? tapped;
      await tester.pumpWidget(MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          bottomNavigationBar: FloatingNavBar(
            items: items,
            selectedIndex: selected,
            onSelected: (i) => tapped = i,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return tapped;
    }

    testWidgets('every tab fits and reports the index it was given',
        (tester) async {
      await pumpBar(tester);
      for (final i in items) {
        expect(find.text(i.label), findsOneWidget);
      }

      int? tapped;
      await tester.pumpWidget(MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          bottomNavigationBar: FloatingNavBar(
            items: items,
            selectedIndex: 0,
            onSelected: (i) => tapped = i,
          ),
        ),
      ));
      await tester.tap(find.text('Debts'));
      await tester.pumpAndSettle();
      expect(tapped, 3);
    });

    testWidgets('only the selected tab carries the pill', (tester) async {
      await pumpBar(tester, selected: 2);
      expect(fillOf(tester, 'Dues'), isNot(Colors.transparent));
      expect(fillOf(tester, 'Home'), Colors.transparent);
      expect(fillOf(tester, 'More'), Colors.transparent);
    });

    testWidgets('five tabs still fit on a narrow phone', (tester) async {
      // The test surface is 800px wide; a real phone is ~360dp, which is where
      // five labelled tabs would overflow if the layout were not flexible.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpBar(tester);
      for (final i in items) {
        expect(find.text(i.label), findsOneWidget);
      }
      // A RenderFlex overflow would have been thrown by now.
      expect(tester.takeException(), isNull);
    });

    testWidgets('the bar floats clear of the screen edges', (tester) async {
      await pumpBar(tester);
      final screen = tester.getSize(find.byType(MaterialApp));
      final bar = tester.getRect(find.byType(DecoratedBox).first);
      expect(bar.left, greaterThan(0));
      expect(bar.right, lessThan(screen.width));
      expect(bar.bottom, lessThan(screen.height));
    });
  });

  group('SegmentedTabs', () {
    Future<void> pumpTabs(WidgetTester tester, String selected,
        {void Function(String)? onChanged}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Center(
            child: SegmentedTabs<String>(
              segments: const [
                ('week', 'Week'),
                ('month', 'Month'),
                ('year', 'Year'),
                ('fy', 'FY'),
                ('custom', 'Custom'),
              ],
              selected: selected,
              onChanged: onChanged ?? (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows every segment and tints only the selected one',
        (tester) async {
      await pumpTabs(tester, 'month');
      for (final l in ['Week', 'Month', 'Year', 'FY', 'Custom']) {
        expect(find.text(l), findsOneWidget);
      }
      expect(fillOf(tester, 'Month'), isNot(Colors.transparent));
      expect(fillOf(tester, 'Week'), Colors.transparent);
      expect(fillOf(tester, 'Custom'), Colors.transparent);
    });

    testWidgets('five segments still fit on a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpTabs(tester, 'month');
      for (final l in ['Week', 'Month', 'Year', 'FY', 'Custom']) {
        expect(find.text(l), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a segment reports its value', (tester) async {
      String? picked;
      await pumpTabs(tester, 'month', onChanged: (v) => picked = v);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      expect(picked, 'custom');
    });
  });
}
