import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_bloc.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_state.dart';
import 'package:wheres_the_car/shared/widgets/availability_gauge.dart';
import 'package:wheres_the_car/shared/widgets/sheet_detail_header.dart';
import 'package:wheres_the_car/shared/widgets/state_cards.dart';

class BikeStationDetailView extends StatelessWidget {
  const BikeStationDetailView({required this.stationUid, super.key});

  final String stationUid;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => BikeStationBloc(stationUid: stationUid),
      child: BlocBuilder<BikeStationBloc, BikeStationState>(
        buildWhen: (p, n) => p.name != n.name,
        builder: (context, state) {
          final title = state.name.isNotEmpty ? state.name : stationUid;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetDetailHeader(
                title: title,
                favorite: Favorite(
                  type: FavoriteType.bikeStation,
                  refId: stationUid,
                  title: title,
                ),
              ),
              const Flexible(child: _StationSheet()),
            ],
          );
        },
      ),
    );
  }
}

class _StationSheet extends StatelessWidget {
  const _StationSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<BikeStationBloc, BikeStationState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 56),
          children: [
            if (state.loading) ...const [
              ShimmerRow(height: 120),
              SizedBox(height: 16),
              ShimmerRow(),
              ShimmerRow(),
            ] else if (state.error != null) ...[
              // Static station-info fetch failed outright: no name/capacity,
              // nothing meaningful to show under it.
              ErrorStateCard(message: state.error!),
            ] else ...[
              // A confirmed zero (state.hasLiveData) reads differently from a
              // stream that never came up (liveError set, hasLiveData still
              // false) — the banner is what makes that distinction visible
              // instead of a bare "0" looking the same either way (F27).
              if (state.liveError != null && !state.hasLiveData)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _LiveDataNotice(message: state.liveError!),
                ),
              AvailabilityGauge(
                available: state.available,
                docks: state.returnDocks,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.pedal_bike_rounded,
                      size: 24,
                      color: cs.onSurface,
                    ),
                    const SizedBox(width: 6),
                    const Text('YouBike 2.0', style: AppTextStyles.bodySmall),
                    const Spacer(),
                    Text(
                      '${state.generalBikes}',
                      style: AppTextStyles.bodyRegular.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      ' 輛',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.electric_bike_rounded,
                      size: 24,
                      color: cs.onSurface,
                    ),
                    const SizedBox(width: 6),
                    const Text('YouBike 2.0E', style: AppTextStyles.bodySmall),
                    const Spacer(),
                    Text(
                      '${state.electricBikes}',
                      style: AppTextStyles.bodyRegular.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      ' 輛',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Compact inline notice for a live availability stream that never came up —
/// deliberately smaller than [ErrorStateCard] since the station's static info
/// and (stale) counts are still shown underneath it.
class _LiveDataNotice extends StatelessWidget {
  const _LiveDataNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.cloud_off_rounded, size: 16, color: cs.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: AppTextStyles.bodySmall.copyWith(color: cs.error),
          ),
        ),
      ],
    );
  }
}
