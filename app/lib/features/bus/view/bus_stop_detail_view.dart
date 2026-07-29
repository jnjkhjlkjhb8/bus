import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_bus/app/router/app_routes.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/core/haptics/haptic_service.dart';
import 'package:wheres_the_bus/data/models/bus_models.dart';
import 'package:wheres_the_bus/data/models/eta_format.dart';
import 'package:wheres_the_bus/data/models/favorite.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_stop_bloc.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_stop_event.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_stop_state.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';
import 'package:wheres_the_bus/shared/motion/stagger.dart';
import 'package:wheres_the_bus/shared/widgets/error_state_view.dart';
import 'package:wheres_the_bus/shared/widgets/eta_list_tile.dart';
import 'package:wheres_the_bus/shared/widgets/sheet_detail_header.dart';

part '../widgets/bus_stop_sheet_widgets.dart';
part '../widgets/bus_stop_skeleton_widgets.dart';
part '../widgets/bus_stop_eta_tile_widgets.dart';

class BusStopDetailView extends StatelessWidget {
  const BusStopDetailView({
    required this.stopName,
    this.stopId,
    this.city,
    this.onFocusStation,
    this.bloc,
    super.key,
  });

  final String stopName;
  final String? stopId;
  final String? city;

  /// 選中的成員站座標變更時通知外層移動地圖（首頁用；獨立頁自己有地圖時可傳自身的移動函式）。
  final ValueChanged<LatLng>? onFocusStation;

  /// 呼叫端已 provide 的 [BusStopBloc]（例如同時要畫地圖 marker 的獨立頁）。
  /// 省略時由本 widget 自建並 provide 唯一一份。
  final BusStopBloc? bloc;

  Favorite _favorite() => Favorite(
    type: FavoriteType.busStop,
    refId: (stopId?.isNotEmpty ?? false) ? stopId! : stopName,
    title: stopName,
    subtitle: city ?? '',
  );

  @override
  Widget build(BuildContext context) {
    final content = BlocListener<BusStopBloc, BusStopState>(
      listenWhen: (p, n) => p.selectedStationUid != n.selectedStationUid,
      listener: (context, state) {
        final uid = state.selectedStationUid;
        if (uid == null || onFocusStation == null) return;
        final m = state.members.where((m) => m.stationUid == uid).firstOrNull;
        if (m != null) onFocusStation!(LatLng(m.lat, m.lon));
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetDetailHeader(
            title: stopName,
            subtitle: const _StopMeta(),
            favorite: _favorite(),
          ),
          const Flexible(child: _StopSheet()),
        ],
      ),
    );

    final existing = bloc;
    if (existing != null) {
      return BlocProvider<BusStopBloc>.value(value: existing, child: content);
    }
    return BlocProvider(
      create: (context) =>
          BusStopBloc(i18n: AppI18n.of(context), stopId: stopId, city: city),
      child: content,
    );
  }
}
