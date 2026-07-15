import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_car/features/rail/view/home_rail_query_sheet.dart';
import 'package:wheres_the_car/features/rail/widgets/rail_query_sheet.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/sheet_detail_header.dart';

/// Home sheet second-level view for a TRA/THSR station. Doesn't board trains
/// itself — it seeds the shared query form with this station as the origin and
/// pushes it onto the home sheet navigator.
class RailStationDetailView extends StatelessWidget {
  const RailStationDetailView({
    required this.system,
    required this.stationId,
    required this.name,
    super.key,
  });

  final RailSystem system;
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
                  '查詢經過本站的班次時刻',
                  style: AppTextStyles.bodyRegular.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _QueryButton(
                  system: system,
                  stationId: stationId,
                  name: name,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the query form pre-seeded with this station on the enclosing (home
/// sheet) navigator. Matches rail_result_card's primary button style: filled,
/// 44 high.
class _QueryButton extends StatelessWidget {
  const _QueryButton({
    required this.system,
    required this.stationId,
    required this.name,
  });

  final RailSystem system;
  final String stationId;
  final String name;

  void _handleTap(BuildContext context) {
    unawaited(HapticService.instance.lightTap());
    unawaited(
      Navigator.of(context).push(
        PagedSheetRoute<void>(
          scrollConfiguration: const SheetScrollConfiguration(),
          initialOffset: AppSheetSnap.tall,
          snapGrid: const SheetSnapGrid(
            snaps: [AppSheetSnap.peek, AppSheetSnap.tall, AppSheetSnap.full],
          ),
          builder: (_) => HomeRailQuerySheet(
            preset: RailQueryPreset(
              system: system,
              originName: name,
              originId: stationId,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () => _handleTap(context),
      semanticLabel: '查班次',
      child: Container(
        height: 44,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
        child: Text(
          '查班次',
          style: AppTextStyles.bodyRegular.copyWith(
            color: cs.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
