import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_event.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_state.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_car/features/rail/rail_navigation_request.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

/// 高鐵單站卡片：站名/收藏 header + 導往高鐵查詢畫面的交接按鈕。
///
/// THSR 沒有單站即時看板 API（`ThsrRepository` 只有 O/D `timetable`/`delay`），
/// 因此不比照台鐵捏造班次清單；改為精簡卡片，導向既有的高鐵查詢畫面並預帶本站
/// 為出發站。首頁第二層 sheet 用；不持有地圖，不需要自己的 bloc（無非同步資料）。
class ThsrStationDetailView extends StatelessWidget {
  const ThsrStationDetailView({
    required this.stationId,
    required this.name,
    super.key,
  });

  final String stationId;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailHeader(stationId: stationId, name: name),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '查詢經過本站的高鐵班次時刻',
                  style: AppTextStyles.bodyRegular.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _QueryButton(stationId: stationId, name: name),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 站名 + 收藏鍵 header，樣式與 bus/bike/台鐵單站 detail 一致。
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.stationId, required this.name});

  final String stationId;
  final String name;

  Favorite _favorite() =>
      Favorite(type: FavoriteType.railStation, refId: stationId, title: name);

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

/// 導往高鐵查詢畫面的主要按鈕；預帶本站為出發站，比照
/// rail_result_card 的 `_BookButton` 風格（primary bg、44 高）。
class _QueryButton extends StatelessWidget {
  const _QueryButton({required this.stationId, required this.name});

  final String stationId;
  final String name;

  void _handleTap(BuildContext context) {
    unawaited(HapticService.instance.lightTap());
    RailNavigationRequest.set(
      stationId: stationId,
      stationName: name,
      system: RailSystem.thsr,
    );
    unawaited(context.push('/rail'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () => _handleTap(context),
      semanticLabel: '查高鐵班次',
      child: Container(
        height: 44,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
        child: Text(
          '查高鐵班次',
          style: AppTextStyles.bodyRegular.copyWith(
            color: cs.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
