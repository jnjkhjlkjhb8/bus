import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wheres_the_car/shared/widgets/maintenance_banner.dart';
import 'package:wheres_the_car/shared/widgets/nav_mini_bar.dart';
import 'package:wheres_the_car/shared/widgets/offline_banner.dart';

class MainScaffold extends StatelessWidget {
  const MainScaffold({required this.shell, super.key});

  final StatefulNavigationShell shell;

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
