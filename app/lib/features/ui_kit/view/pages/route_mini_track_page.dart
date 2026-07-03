import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/eta_list_tile.dart';
import 'package:wheres_the_car/shared/widgets/route_mini_track.dart';

class RouteMiniTrackPage extends StatelessWidget {
  const RouteMiniTrackPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const DetailAppBar(title: 'Route Mini Track'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const ShowcaseSection(
            title: 'Approaching (primary)',
            child: RouteMiniTrack(progress: 0.62),
          ),
          const ShowcaseSection(
            title: 'Arriving',
            child: RouteMiniTrack(progress: 0.92, color: AppTheme.etaArriving),
          ),
          const ShowcaseSection(
            title: 'Scheduled / no live vehicle',
            child: RouteMiniTrack(),
          ),
          const ShowcaseSection(
            title: 'With endpoint labels',
            child: RouteMiniTrack(
              progress: 0.45,
              originLabel: '陸光二村',
              destinationLabel: '統領百貨',
            ),
          ),
          ShowcaseSection(
            title: 'EtaListTile — coming-soon highlight + track',
            child: EtaListTile(
              routeNo: '261',
              destination: '銘傳大學',
              status: EtaStatus.arriving(),
              highlighted: true,
              track: const RouteMiniTrack(
                progress: 0.92,
                color: AppTheme.etaArriving,
              ),
            ),
          ),
          ShowcaseSection(
            title: 'EtaListTile — default + track',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  EtaListTile(
                    routeNo: '106',
                    destination: '中壢火車站',
                    status: EtaStatus.minutes(8),
                    track: const RouteMiniTrack(progress: 0.3),
                  ),
                  Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  EtaListTile(
                    routeNo: '130',
                    destination: '南崁',
                    status: EtaStatus.unknown(),
                    track: const RouteMiniTrack(),
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
