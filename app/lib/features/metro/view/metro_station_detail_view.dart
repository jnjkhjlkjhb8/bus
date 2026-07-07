import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/data/models/metro_map_models.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_event.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_state.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_bloc.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_event.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_state.dart';
import 'package:wheres_the_car/shared/motion/stagger.dart';
import 'package:wheres_the_car/shared/widgets/eta_list_tile.dart';
import 'package:wheres_the_car/shared/widgets/state_cards.dart';
import 'package:wheres_the_car/shared/widgets/transport_icon.dart';

part '../widgets/metro_station_detail_widgets.dart';

const _kLineNames = <String, String>{
  'BL': '板南線',
  'R': '淡水信義線',
  'G': '松山新店線',
  'BR': '文湖線',
  'O': '中和新蘆線',
};

final RegExp _digits = RegExp(r'\d+');

String _lineCode(String id) => id.split('_').first.replaceAll(_digits, '');

String _lineName(String id) => _kLineNames[_lineCode(id)] ?? _lineCode(id);

TransportType _getTransportType(String line) {
  switch (line) {
    case 'BL':
      return TransportType.mrtBL;
    case 'R':
      return TransportType.mrtR;
    case 'G':
      return TransportType.mrtG;
    case 'BR':
      return TransportType.mrtBR;
    case 'O':
      return TransportType.mrtO;
    default:
      return TransportType.mrtBL;
  }
}

/// 捷運單站可嵌入內容：站名/收藏 header + 到站清單 + 首末班，不持有地圖。
/// 首頁第二層 sheet 與 `/metro` 地圖內的站點面板共用同一份內容
/// （後者透過 `metro_screen.dart` 內既有的 `_StationDetailSheet` 用法）。
///
/// TRTC 為目前唯一支援的捷運系統；呼叫端（例如首頁 dispatch）於此固定帶入。
class MetroStationDetailView extends StatelessWidget {
  const MetroStationDetailView({
    required this.system,
    required this.stationId,
    required this.name,
    this.onClose,
    super.key,
  });

  final String system;
  final String stationId;
  final String name;

  /// 關閉鈕的回呼；省略時不顯示關閉鈕（首頁第二層 sheet 用法）。
  /// `/metro` 地圖內的站點面板會傳入此參數以顯示關閉鈕。
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MetroEtaBloc()..add(LoadMetroEta(system, stationId)),
      child: _StationDetailSheet(
        system: system,
        station: MetroMapStation(id: stationId, name: name, x: 0, y: 0),
        onClose: onClose,
      ),
    );
  }
}
