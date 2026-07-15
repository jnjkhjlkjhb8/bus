import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/shared/widgets/route_tab_bar.dart';

void main() {
  // The home/bus sheets build RouteTabBar once inside a nested Navigator route
  // that never re-runs its builder, so the bar must derive its colour from the
  // live theme rather than a colour passed in at build time — otherwise it
  // stays stuck in the launch theme after a light/dark switch.
  Widget host(Brightness brightness, TabController controller) => MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      ),
    ),
    home: Scaffold(
      body: RouteTabBar(
        controller: controller,
        tabs: const ['A', 'B'],
        raised: true,
      ),
    ),
  );

  Color barColor(WidgetTester tester) => tester
      .widget<ColoredBox>(
        find.descendant(
          of: find.byType(RouteTabBar),
          matching: find.byType(ColoredBox),
        ),
      )
      .color;

  testWidgets('raised bar tracks the active theme brightness', (tester) async {
    final controller = TabController(length: 2, vsync: tester);
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(Brightness.light, controller));
    await tester.pumpAndSettle();
    final lightBar = barColor(tester);
    expect(
      lightBar,
      ColorScheme.fromSeed(
        seedColor: Colors.blue,
      ).surfaceContainerLow,
    );

    await tester.pumpWidget(host(Brightness.dark, controller));
    await tester.pumpAndSettle();
    final darkBar = barColor(tester);
    expect(
      darkBar,
      ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ).surfaceContainerLow,
    );

    expect(lightBar, isNot(darkBar));
  });
}
