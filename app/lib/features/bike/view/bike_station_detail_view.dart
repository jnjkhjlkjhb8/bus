import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wheres_the_bus/app/router/app_routes.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/data/models/favorite.dart';
import 'package:wheres_the_bus/features/bike/bloc/bike_station_bloc.dart';
import 'package:wheres_the_bus/features/bike/bloc/bike_station_state.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/widgets/app_button.dart';
import 'package:wheres_the_bus/shared/widgets/availability_gauge.dart';
import 'package:wheres_the_bus/shared/widgets/sheet_detail_header.dart';
import 'package:wheres_the_bus/shared/widgets/state_cards.dart';

class BikeStationDetailView extends StatelessWidget {
  const BikeStationDetailView({
    required this.stationUid,
    this.bloc,
    this.name,
    this.lat,
    this.lon,
    super.key,
  });

  final String stationUid;

  /// A [BikeStationBloc] the caller already owns (the standalone screen also
  /// draws the map from it). Omitted, this widget creates and provides the
  /// only one; passing it in avoids a second static fetch and live stream.
  final BikeStationBloc? bloc;

  /// What the caller already knows about the station. Seeds the bloc it
  /// creates, so the title and the directions action are right on the first
  /// frame instead of waiting on the static fetch. Ignored when [bloc] is
  /// given — that bloc was seeded by whoever built it.
  final String? name;
  final double? lat;
  final double? lon;

  @override
  Widget build(BuildContext context) {
    final content = BlocBuilder<BikeStationBloc, BikeStationState>(
      buildWhen: (p, n) =>
          p.name != n.name ||
          p.capacity != n.capacity ||
          p.updatedAt != n.updatedAt,
      builder: (context, state) {
        final title = state.name.isNotEmpty ? state.name : stationUid;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetDetailHeader(
              title: title,
              subtitle: _StationMeta(
                capacity: state.capacity,
                updatedAt: state.updatedAt,
              ),
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
    );
    final existing = bloc;
    if (existing != null) {
      return BlocProvider<BikeStationBloc>.value(
        value: existing,
        child: content,
      );
    }
    return BlocProvider(
      create: (_) => BikeStationBloc(
        stationUid: stationUid,
        name: name,
        lat: lat,
        lon: lon,
      ),
      child: content,
    );
  }
}

/// Header subtitle: the station's size and how fresh its counts are — the two
/// facts that turn a bare number into a reading. Capacity was fetched but
/// never shown before, and a live-streamed count carried no timestamp at all.
class _StationMeta extends StatelessWidget {
  const _StationMeta({required this.capacity, required this.updatedAt});

  final int capacity;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final at = updatedAt;
    if (capacity <= 0 && at == null) return const SizedBox.shrink();

    final label = AppTextStyles.bodySmall.copyWith(
      color: cs.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          if (capacity > 0)
            Text(AppI18n.of(context).bikeDockCount(capacity), style: label),
          if (capacity > 0 && at != null) Text(' · ', style: label),
          if (at != null) ...[
            // Mono-for-Time: a clock reading, not a ticking "N 分鐘前" that
            // would need a timer redrawing the header every second.
            Text(
              '${at.hour.toString().padLeft(2, '0')}:'
              '${at.minute.toString().padLeft(2, '0')}',
              style: AppTextStyles.memo.copyWith(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontFeatures: AppTextStyles.tabularFigures,
              ),
            ),
            Text(AppI18n.of(context).bikeUpdatedSuffix, style: label),
          ],
        ],
      ),
    );
  }
}

class _StationSheet extends StatelessWidget {
  const _StationSheet();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BikeStationBloc, BikeStationState>(
      builder: (context, state) {
        // Column, not ListView: the sheet measures its own content height and
        // an unbounded scrollable inside it has nothing to measure against.
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.loading) ...const [
                ShimmerRow(height: 22),
                SizedBox(height: 16),
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
                    child: _LiveDataNotice(error: state.liveError!),
                  ),
                AvailabilityGauge(
                  available: state.available,
                  docks: state.returnDocks,
                  capacity: state.capacity,
                  generalBikes: state.generalBikes,
                  electricBikes: state.electricBikes,
                  hasLiveData: state.hasLiveData,
                ),
                if (state.lat != 0 || state.lon != 0) ...[
                  const SizedBox(height: 20),
                  _WalkThereButton(
                    lat: state.lat,
                    lon: state.lon,
                    name: state.name,
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Hands the station off to the app's own planner with the destination already
/// filled in. Without it the sheet is a dead end: it answers "is there a bike"
/// and then offers no way to go get it. Routing through `/go` rather than the
/// platform maps app keeps the transit modes this app actually knows about —
/// and the live ETAs behind them — instead of dropping the user into a
/// walking-only view somewhere else.
class _WalkThereButton extends StatelessWidget {
  const _WalkThereButton({
    required this.lat,
    required this.lon,
    required this.name,
  });

  final double lat;
  final double lon;
  final String name;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: AppI18n.of(context).bikePlanRoute,
      icon: Icons.directions_rounded,
      onPressed: () => unawaited(
        context.push(
          AppRoutes.goToDestination(
            // The station UID is never a usable label; fall back to a coarse
            // one rather than pushing an empty destination field.
            name: name.isNotEmpty
                ? name
                : AppI18n.of(context).bikeStationFallbackName,
            lat: lat,
            lon: lon,
          ),
        ),
      ),
    );
  }
}

/// Compact inline notice for a live availability stream that never came up —
/// deliberately smaller than [ErrorStateCard] since the station's static info
/// and (stale) counts are still shown underneath it.
class _LiveDataNotice extends StatelessWidget {
  const _LiveDataNotice({required this.error});

  final AppError error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.cloud_off_rounded, size: 16, color: cs.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            error.titleOf(AppI18n.of(context)),
            style: AppTextStyles.bodySmall.copyWith(color: cs.error),
          ),
        ),
      ],
    );
  }
}
