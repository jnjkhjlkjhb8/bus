import 'package:flutter/material.dart';
import 'package:wheres_the_car/shared/widgets/maintenance_banner.dart';
import 'package:wheres_the_car/shared/widgets/nav_mini_bar.dart';
import 'package:wheres_the_car/shared/widgets/offline_banner.dart';

/// Shell around the app's single StatefulShellRoute branch: routed content
/// fills the window, with system banners overlaid at the top and the floating
/// [NavMiniBar] at the bottom. Banners overlay rather than occupy layout space
/// so a full-bleed map branch stays edge-to-edge when one appears.
class MainScaffold extends StatelessWidget {
  const MainScaffold({required this.shell, super.key});

  /// The active branch navigator. Typed [Widget] (the router passes a
  /// `StatefulNavigationShell`) so tests can render the scaffold around any
  /// content.
  final Widget shell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        Positioned.fill(child: shell),
        const Align(
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [MaintenanceBanner(), OfflineBanner()],
          ),
        ),
        const Align(alignment: Alignment.bottomCenter, child: NavMiniBar()),
      ],
    ),
  );
}
