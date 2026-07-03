import 'dart:typed_data';
import 'package:wheres_the_car/data/generated/bus.pb.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';

/// 公車資料解碼
class BusDecoder {
  const BusDecoder._();
  static const BusDecoder instance = BusDecoder._();

  List<BusStopEtaViewModel> decodeRouteEta(Uint8List data) {
    final arrival = Bus_RouteArrival.fromBuffer(data);
    return arrival.stops.map((s) {
      return BusStopEtaViewModel(
        stopUid: s.stopUid,
        direction: s.direction,
        sequence: s.stopSequence,
        estimateSeconds: s.estimate,
        nextBusTime: s.nextBusTime,
        stopStatus: s.stopStatus,
        vehiclePlates: s.buses.map((b) => b.plateNumb).toList(),
      );
    }).toList();
  }

  BusRouteViewModel decodeStatic(Uint8List data) {
    final route = Bus_subroute.fromBuffer(data);
    final dir0 = route.directions[0];
    final dir1 = route.directions[1];
    return BusRouteViewModel(
      subRouteUid: route.subRouteUID,
      routeName: route.routeName,
      subRouteName: route.subRouteName,
      departureStopName: route.departureStopName,
      destinationStopName: route.destinationStopName,
      city: route.city,
      headsignGo: dir0?.destinationStopName ?? '',
      headsignReturn: dir1?.destinationStopName ?? '',
      operatorName: '',
      stopsGo: dir0?.stops.map(_stop).toList() ?? [],
      stopsReturn: dir1?.stops.map(_stop).toList() ?? [],
      geometryGo: dir0?.geometry ?? '',
      geometryReturn: dir1?.geometry ?? '',
      fare: route.hasFare() ? route.fare : null,
    );
  }

  BusStopModel _stop(Bus_stop s) => BusStopModel(
    stopUid: s.stopUID,
    stopName: s.stopName,
    sequence: s.stopSequence,
    lat: s.positionLat,
    lon: s.positionLon,
  );

  Bus_DailyTimetables decodeDaily(Uint8List data) {
    return Bus_DailyTimetables.fromBuffer(data);
  }

  int? etaMinutes(int estimateSecs) {
    if (estimateSecs <= 0) return null;
    return (estimateSecs / 60).ceil();
  }
}
