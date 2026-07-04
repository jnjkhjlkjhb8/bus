import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';
import 'package:wheres_the_car/data/models/eta_format.dart';

enum BusArrivalStatus { arriving, approaching, minutes, unknown }

class BusStopEtaViewModel extends Equatable {
  const BusStopEtaViewModel({
    required this.stopUid,
    required this.direction,
    required this.sequence,
    required this.estimateSeconds,
    required this.nextBusTime,
    required this.stopStatus,
    required this.vehiclePlates,
  });

  final String stopUid;
  final int direction;
  final int sequence;
  final int estimateSeconds;
  final String nextBusTime;
  final int stopStatus;
  final List<String> vehiclePlates;

  int get estimateMinutes => etaCeilMinutes(estimateSeconds);

  String? get displayLabel => busStopDisplayLabel(
    estimateSeconds: estimateSeconds,
    stopStatus: stopStatus,
    nextBusTime: nextBusTime,
  );

  BusArrivalStatus get status {
    if (stopStatus == 0 && estimateSeconds == 0) {
      return BusArrivalStatus.arriving;
    }
    if (estimateSeconds > 0 && estimateSeconds < 60) {
      return BusArrivalStatus.approaching;
    }
    if (estimateSeconds > 0) return BusArrivalStatus.minutes;
    return BusArrivalStatus.unknown;
  }

  @override
  List<Object?> get props => [
    stopUid,
    direction,
    sequence,
    estimateSeconds,
    nextBusTime,
    stopStatus,
    vehiclePlates,
  ];
}

class BusStopModel extends Equatable {
  const BusStopModel({
    required this.stopUid,
    required this.stopName,
    required this.sequence,
    this.lat = 0,
    this.lon = 0,
  });
  final String stopUid;
  final String stopName;
  final int sequence;
  final double lat;
  final double lon;
  @override
  List<Object?> get props => [stopUid, stopName, sequence, lat, lon];
}

class BusRouteViewModel extends Equatable {
  const BusRouteViewModel({
    required this.subRouteUid,
    required this.routeName,
    required this.subRouteName,
    required this.departureStopName,
    required this.destinationStopName,
    required this.city,
    required this.headsignGo,
    required this.headsignReturn,
    required this.operatorName,
    this.stopsGo = const [],
    this.stopsReturn = const [],
    this.geometryGo = '',
    this.geometryReturn = '',
    this.fare,
  });

  final String subRouteUid;
  final String routeName;
  final String subRouteName;
  final String departureStopName;
  final String destinationStopName;
  final String city;
  final String headsignGo;
  final String headsignReturn;
  final String operatorName;
  final List<BusStopModel> stopsGo;
  final List<BusStopModel> stopsReturn;
  final String geometryGo;
  final String geometryReturn;
  final BusFareInfo? fare;

  @override
  List<Object?> get props => [
    subRouteUid,
    routeName,
    subRouteName,
    departureStopName,
    destinationStopName,
    city,
    headsignGo,
    headsignReturn,
    fare,
  ];
}
