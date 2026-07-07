import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_car/features/rail/rail_navigation_request.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/sheet_detail_header.dart';

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
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetDetailHeader(
            title: name,
            favorite: Favorite(
              type: FavoriteType.railStation,
              refId: stationId,
              title: name,
            ),
          ),
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
