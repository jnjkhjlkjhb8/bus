import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_bloc.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_event.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_state.dart';
import 'package:wheres_the_car/features/rail/view/rail_train_screen.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_card.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/sheet_detail_header.dart';
import 'package:wheres_the_car/shared/widgets/state_cards.dart';
import 'package:wheres_the_car/shared/widgets/train_type_chip.dart';

String _todayIso() {
  final now = DateTime.now();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '${now.year}-$m-$d';
}

/// Lists every train currently passing through [stationId] as OD-style cards,
/// each running from this station to that train's own terminus. Reuses the live
/// board stream (via [TraStationBloc]); the departure board has no terminus
/// arrival time, so unlike the O/D timetable card there is no arrival/duration.
class TraStationBoardView extends StatelessWidget {
  const TraStationBoardView({
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
          SheetDetailHeader(
            title: name,
            favorite: Favorite(
              type: FavoriteType.railStation,
              refId: stationId,
              title: name,
            ),
          ),
          Flexible(child: _Board(stationId: stationId, originName: name)),
        ],
      ),
    );
  }
}

/// Full-page version of the station board, pushed from search (`/rail/station`).
/// Same live board as [TraStationBoardView], hosted in a [Scaffold] with a
/// back/favorite app bar instead of a bottom sheet.
class TraStationScreen extends StatelessWidget {
  const TraStationScreen({
    required this.stationId,
    required this.name,
    super.key,
  });

  final String stationId;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: DetailAppBar(
        title: name,
        actions: [
          FavoriteToggleButton(
            favorite: Favorite(
              type: FavoriteType.railStation,
              refId: stationId,
              title: name,
            ),
          ),
        ],
      ),
      body: BlocProvider(
        create: (_) => TraStationBloc()..add(LoadTraStation(stationId)),
        child: _Board(stationId: stationId, originName: name),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.stationId, required this.originName});

  final String stationId;
  final String originName;

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
            padding: EdgeInsets.fromLTRB(16, 8, 16, 40),
            child: Column(
              children: [
                ShimmerRow(height: 84),
                SizedBox(height: 10),
                ShimmerRow(height: 84),
                SizedBox(height: 10),
                ShimmerRow(height: 84),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          itemCount: state.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) =>
              _BoardCard(item: state.items[i], originName: originName),
        );
      },
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.item, required this.originName});

  final TraLiveBoardItem item;
  final String originName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final delayed = item.delayMinutes > 0;

    return Pressable(
      onTap: () {
        unawaited(HapticService.instance.lightTap());
        unawaited(
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RailTrainScreen(
                type: item.trainType,
                trainNo: item.trainNo,
                date: _todayIso(),
              ),
            ),
          ),
        );
      },
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TrainTypeChip(type: item.trainType),
                const SizedBox(width: 8),
                Text(
                  item.trainNo,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontFeatures: AppTextStyles.tabularFigures,
                  ),
                ),
                const Spacer(),
                if (delayed)
                  Text(
                    '+${item.delayMinutes}分',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w600,
                      fontFeatures: AppTextStyles.tabularFigures,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  width: 68,
                  child: Text(
                    item.departureTime,
                    style: AppTextStyles.memo.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: delayed ? cs.error : cs.onSurface,
                      fontFeatures: AppTextStyles.tabularFigures,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        originName,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '往 ${item.destStation}',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
