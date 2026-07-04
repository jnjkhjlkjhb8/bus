import 'dart:typed_data';
import 'package:wheres_the_car/data/generated/bus.pb.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';

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
      fare: route.hasFare() ? _fare(route.fare) : null,
    );
  }

  BusFareInfo _fare(Bus_Fare f) => BusFareInfo(
    pricingType: f.farePricingType,
    isFreeBus: f.isFreeBus,
    sectionFaresJson: f.sectionFaresJson,
    stageFaresJson: f.stageFaresJson,
    odFaresJson: f.odFaresJson,
  );

  BusStopModel _stop(Bus_stop s) => BusStopModel(
    stopUid: s.stopUID,
    stopName: s.stopName,
    sequence: s.stopSequence,
    lat: s.positionLat,
    lon: s.positionLon,
  );

  BusDailyTimetable decodeDaily(Uint8List data) {
    final proto = Bus_DailyTimetables.fromBuffer(data);
    return BusDailyTimetable(
      directions: {
        for (final entry in proto.direction.entries)
          entry.key: [
            for (final t in entry.value.dailyTimetables)
              BusDailyTrip(
                tripId: t.tripID,
                isLowFloor: t.isLowFloor,
                stopTimes: [
                  for (final s in t.stopTimes)
                    BusStopTime(
                      stopSequence: s.stopSequence,
                      departureTime: s.departureTime,
                      arrivalTime: s.arrivalTime,
                    ),
                ],
              ),
          ],
      },
    );
  }
}
