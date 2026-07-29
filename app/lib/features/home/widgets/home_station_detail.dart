import 'package:flutter/material.dart';
import 'package:wheres_the_bus/data/models/near_models.dart';
import 'package:wheres_the_bus/features/bike/view/bike_station_detail_view.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_stop_bloc.dart';
import 'package:wheres_the_bus/features/bus/view/bus_stop_detail_view.dart';
import 'package:wheres_the_bus/features/metro/view/metro_station_detail_view.dart';
import 'package:wheres_the_bus/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_bus/features/rail/view/rail_station_detail_view.dart';
import 'package:wheres_the_bus/shared/widgets/bottom_sheet_shell.dart';

/// 依站別回傳首頁第二層 sheet 要顯示的 detail 內容。
///
/// 外層的 [SheetPageTopInset] 讓第二層跟第一層一樣，往上拉時內容會逐漸讓開狀態列。
///
/// [bloc] 由首頁持有並傳入（公車才有），讓 sheet 的成員 chip 和地圖上的站牌膠囊
/// 共用同一份 selectedStationUid；省略時 detail view 自建一份。
Widget stationDetailPage(
  NearStationViewModel station, {
  BusStopBloc? bloc,
}) => SheetPageTopInset(child: _stationDetailContent(station, bloc));

Widget _stationDetailContent(
  NearStationViewModel station,
  BusStopBloc? busStopBloc,
) {
  switch (station.type) {
    case NearStationType.bus:
      return BusStopDetailView(
        stopName: station.stationName,
        stopId: station.stationId,
        bloc: busStopBloc,
        // onFocusStation 省略：選中的成員站已由地圖上的膠囊翻墨色回答，
        // 再自動平移會在使用者捲動清單時把地圖抽走。
      );
    case NearStationType.bike:
      return BikeStationDetailView(
        stationUid: station.stationId,
        name: station.stationName,
        lat: station.lat,
        lon: station.lon,
      );
    case NearStationType.mrt:
      // TRTC 為固定值：NearStationViewModel 未帶捷運系統欄位，
      // 且目前 app 內僅支援台北捷運 (TRTC)；等有第二個系統再擴充 model。
      return MetroStationDetailView(
        system: 'TRTC',
        stationId: station.stationId,
        name: station.stationName,
      );
    case NearStationType.tra:
      return RailStationDetailView(
        system: RailSystem.tra,
        stationId: station.stationId,
        name: station.stationName,
      );
    case NearStationType.thsr:
      return RailStationDetailView(
        system: RailSystem.thsr,
        stationId: station.stationId,
        name: station.stationName,
      );
  }
}
