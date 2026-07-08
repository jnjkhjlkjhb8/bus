import 'package:flutter/material.dart';
import 'package:wheres_the_car/data/models/near_models.dart';
import 'package:wheres_the_car/features/bike/view/bike_station_detail_view.dart';
import 'package:wheres_the_car/features/bus/view/bus_stop_detail_view.dart';
import 'package:wheres_the_car/features/metro/view/metro_station_detail_view.dart';
import 'package:wheres_the_car/features/rail/view/thsr_station_detail_view.dart';
import 'package:wheres_the_car/features/rail/view/tra_station_detail_view.dart';

/// 依站別回傳首頁第二層 sheet 要顯示的 detail 內容。
Widget stationDetailPage(NearStationViewModel station) {
  switch (station.type) {
    case NearStationType.bus:
      return BusStopDetailView(
        stopName: station.stationName,
        stopId: station.stationId,
        // onFocusStation 省略：首頁地圖已在 _focusStationOnMap 對站群中心平移；
        // 是否要在切換成員站時再平移，留待手動驗證後決定是否補上。
      );
    case NearStationType.bike:
      return BikeStationDetailView(stationUid: station.stationId);
    case NearStationType.mrt:
      // TRTC 為固定值：NearStationViewModel 未帶捷運系統欄位，
      // 且目前 app 內僅支援台北捷運 (TRTC)；等有第二個系統再擴充 model。
      return MetroStationDetailView(
        system: 'TRTC',
        stationId: station.stationId,
        name: station.stationName,
      );
    case NearStationType.tra:
      return TraStationDetailView(
        stationId: station.stationId,
        name: station.stationName,
      );
    case NearStationType.thsr:
      return ThsrStationDetailView(
        stationId: station.stationId,
        name: station.stationName,
      );
  }
}
