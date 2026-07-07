import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_bloc.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_state.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_event.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_state.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/availability_gauge.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/state_cards.dart';

/// YouBike 單站可嵌入內容：站名/收藏 header + 可借/可還內容，不持有地圖。
/// 首頁第二層 sheet 與 `/bike/station` 獨立頁共用同一份內容。
///
/// 站點無成員子站可切換（單一座標），故不需要 `onFocusStation`。
/// 目前 `/bike/station` 獨立頁的地圖不讀取 bike bloc 狀態，因此本 widget
/// 一律自建並唯一 provide 一份 [BikeStationBloc]。
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
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailHeader(stationUid: stationUid, name: state.name),
              const Flexible(child: _StationSheet()),
            ],
          );
        },
      ),
    );
  }
}

/// 站名 + 收藏鍵 header（取代原獨立頁地圖上方 app bar 的收藏鍵）。
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.stationUid, required this.name});

  final String stationUid;
  final String name;

  Favorite _favorite() => Favorite(
    type: FavoriteType.bikeStation,
    refId: stationUid,
    title: name.isNotEmpty ? name : stationUid,
  );

  void _toggle(BuildContext context) {
    final favorite = _favorite();
    unawaited(HapticService.instance.lightTap());
    final wasSaved = context.read<FavoritesBloc>().state.contains(favorite.id);
    context.read<FavoritesBloc>().add(FavoriteToggled(favorite));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasSaved ? '已取消收藏' : '已加入收藏'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(label: '復原', onPressed: () => _toggle(context)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final favorite = _favorite();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name.isNotEmpty ? name : stationUid,
              style: AppTextStyles.heading2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          BlocBuilder<FavoritesBloc, FavoritesState>(
            buildWhen: (p, n) =>
                p.contains(favorite.id) != n.contains(favorite.id),
            builder: (context, state) {
              final saved = state.contains(favorite.id);
              return Pressable(
                onTap: () => _toggle(context),
                semanticLabel: saved ? '取消收藏' : '收藏',
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    saved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    size: 22,
                    color: cs.onSurface,
                  ),
                ),
              );
            },
          ),
        ],
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
            const SheetDragHandle(),
            const SizedBox(height: 12),
            if (state.loading) ...const [
              ShimmerRow(height: 120),
              SizedBox(height: 16),
              ShimmerRow(),
              ShimmerRow(),
            ] else ...[
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
