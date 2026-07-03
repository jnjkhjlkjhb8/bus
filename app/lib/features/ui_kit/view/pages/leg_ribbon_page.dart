import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/leg_ribbon.dart';
import 'package:wheres_the_car/shared/widgets/transport_icon.dart';

class LegRibbonPage extends StatelessWidget {
  const LegRibbonPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const DetailAppBar(title: 'Leg Ribbon'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Walk → Bus → MRT → Walk',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LegRibbon(
                segments: [
                  LegRibbonSegment(
                    icon: Icon(
                      Icons.directions_walk_rounded,
                      size: 22,
                      color: cs.onSurface,
                    ),
                    minutes: '6',
                    color: cs.outlineVariant,
                  ),
                  LegRibbonSegment(
                    icon: Icon(
                      Icons.directions_bus_rounded,
                      size: 22,
                      color: cs.onSurface,
                    ),
                    minutes: '8',
                    color: cs.onSurfaceVariant,
                  ),
                  const LegRibbonSegment(
                    icon: TransportIcon(type: TransportType.mrtBL, size: 22),
                    minutes: '12',
                    color: AppTheme.mrtBL,
                  ),
                  LegRibbonSegment(
                    icon: Icon(
                      Icons.directions_walk_rounded,
                      size: 22,
                      color: cs.onSurface,
                    ),
                    minutes: '4',
                    color: cs.outlineVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
