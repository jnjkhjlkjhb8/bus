import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/eta_format.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/data/repositories/bus_stop_eta_repository.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_bloc.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_event.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_state.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_event.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_state.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/motion/stagger.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/eta_list_tile.dart';

part '../widgets/bus_stop_sheet_widgets.dart';
part '../widgets/bus_stop_skeleton_widgets.dart';
part '../widgets/bus_stop_eta_tile_widgets.dart';

/// 公車單站可嵌入內容：站名/收藏 header + ETA 清單，不持有地圖。
/// 首頁第二層 sheet 與 `/bus/stop` 獨立頁共用同一份內容。
///
/// 預設會自建 [BusStopBloc]；若呼叫端（例如 `BusStopScreen`）已在外層
/// provide 了同一個 bloc 實例（地圖也需要讀取 members 畫 marker），
/// 可透過 [bloc] 傳入既有實例，這裡就不會重複 provide。
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
          _DetailHeader(stopName: stopName, favorite: _favorite()),
          Flexible(child: _StopSheet(stopName: stopName)),
        ],
      ),
    );

    final existing = bloc;
    if (existing != null) {
      return BlocProvider<BusStopBloc>.value(value: existing, child: content);
    }
    return BlocProvider(
      create: (_) => BusStopBloc(stopId: stopId, city: city),
      child: content,
    );
  }
}

/// 站名 + 收藏鍵 header（取代原獨立頁地圖上方 app bar 的收藏鍵）。
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.stopName, required this.favorite});

  final String stopName;
  final Favorite favorite;

  void _toggle(BuildContext context) {
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stopName,
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
