import 'package:flutter/material.dart';
import 'package:wheres_the_car/shared/widgets/maintenance_banner.dart';
import 'package:wheres_the_car/shared/widgets/nav_mini_bar.dart';
import 'package:wheres_the_car/shared/widgets/offline_banner.dart';

/// Shell around the app's single StatefulShellRoute branch: system banners
/// stacked above the routed content, with the floating [NavMiniBar] overlaid
/// at the bottom.
class MainScaffold extends StatelessWidget {
  const MainScaffold({required this.shell, super.key});

  /// The active branch navigator. Typed [Widget] (the router passes a
  /// `StatefulNavigationShell`) so tests can render the scaffold around any
  /// content.
  final Widget shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const MaintenanceBanner(),
        const OfflineBanner(),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: shell),
              const Align(
                alignment: Alignment.bottomCenter,
                child: NavMiniBar(),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
