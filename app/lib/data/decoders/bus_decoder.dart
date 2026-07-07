import 'dart:typed_data';
import 'package:wheres_the_car/data/generated/bus.pb.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';

class BusDecoder {
  const BusDecoder._();
  static const BusDecoder instance = BusDecoder._();

  List<BusStopEtaViewModel> decodeRouteEta(Uint8List data) {
    final arrival = Bus_RouteArrival.fromBuffer(data);
    final nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return arrival.stops.map((s) {
      final arrivalUnix = s.arrivalUnix.toInt();
      // Prefer the absolute arrival instant when the server sent one: derive
      // the countdown against local time so it stays accurate between pushes. A
      // just-passed instant clamps to 0, which stopStatus 0 reads as 進站中.
      final estimateSeconds = arrivalUnix > 0
          ? (arrivalUnix - nowUnix > 0 ? arrivalUnix - nowUnix : 0)
          : s.estimate;
      return BusStopEtaViewModel(
        stopUid: s.stopUid,
        direction: s.direction,
        sequence: s.stopSequence,
        estimateSeconds: estimateSeconds,
        nextBusTime: s.nextBusTime,
        stopStatus: s.stopStatus,
        arrivalUnix: arrivalUnix,
        vehiclePlates: s.buses.map((b) => b.plateNumb).toList(),
        vehicles: [
          for (final b in s.buses)
            if (b.positionLat != 0 || b.positionLon != 0)
              BusVehiclePosition(
                plate: b.plateNumb,
                lat: b.positionLat,
                lon: b.positionLon,
                azimuth: b.azimuth,
              ),
        ],
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
