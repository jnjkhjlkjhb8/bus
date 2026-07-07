import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_event.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_state.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_bloc.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_event.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_state.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/state_cards.dart';

const List<FontFeature> _tnum = AppTextStyles.tabularFigures;

/// 台鐵單站即時到離站看板：站名/收藏 header + 依發車時間排序的班次清單。
/// 首頁第二層 sheet 用；不持有地圖。
///
/// 自建並唯一 provide 一份 [TraStationBloc]。
class TraStationDetailView extends StatelessWidget {
  const TraStationDetailView({
    required this.stationId,
    required this.name,
    super.key,
  });

  final String stationId;
  final String name;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TraStationBloc()..add(LoadTraStation(stationId)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DetailHeader(stationId: stationId, name: name),
          Flexible(child: _Board(stationId: stationId)),
        ],
      ),
    );
  }
}

/// 站名 + 收藏鍵 header，樣式與 bus/bike 單站 detail 一致。
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.stationId, required this.name});

  final String stationId;
  final String name;

  Favorite _favorite() => Favorite(
    type: FavoriteType.railStation,
    refId: stationId,
    title: name,
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
              name,
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

class _Board extends StatelessWidget {
  const _Board({required this.stationId});

  final String stationId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TraStationBloc, TraStationState>(
      builder: (context, state) {
        if (state.error != null) {
          return ErrorStateView(
            error: state.error!,
            onRetry: () =>
                context.read<TraStationBloc>().add(LoadTraStation(stationId)),
          );
        }
        if (state.loading && state.items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: Column(
              children: [
                ShimmerRow(height: 56),
                SizedBox(height: 10),
                ShimmerRow(height: 56),
                SizedBox(height: 10),
                ShimmerRow(height: 56),
              ],
            ),
          );
        }
        if (state.items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: EmptyStateCard(
              message: '目前沒有列車班次',
              icon: Icons.train_rounded,
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          itemCount: state.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _DepartureRow(item: state.items[i]),
        );
      },
    );
  }
}

class _DepartureRow extends StatelessWidget {
  const _DepartureRow({required this.item});

  final TraLiveBoardItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final delayed = item.delayMinutes > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          _TrainTypeChip(label: item.trainType),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '往${item.destStation}',
                  style: AppTextStyles.bodyRegular.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.direction} · ${item.trainNo}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFeatures: _tnum,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.departureTime,
                style: AppTextStyles.memo.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFeatures: _tnum,
                  color: delayed ? cs.error : cs.onSurface,
                ),
              ),
              if (delayed) ...[
                const SizedBox(height: 4),
                _DelayPill(minutes: item.delayMinutes),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Local equivalent of rail_result_card's private `_TrainTypeBadge`, which
/// cannot be imported across files. No colour map exists for trainType
/// here, so this stays a neutral surface chip rather than inventing one.
class _TrainTypeChip extends StatelessWidget {
  const _TrainTypeChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Local equivalent of rail_result_card's private `_DelayPill`.
class _DelayPill extends StatelessWidget {
  const _DelayPill({required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusStadium),
      ),
      child: Text(
        '誤點 $minutes 分',
        style: AppTextStyles.bodySmall.copyWith(
          fontFeatures: _tnum,
          color: cs.onErrorContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
