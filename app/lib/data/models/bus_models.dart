import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';
import 'package:wheres_the_car/data/models/eta_format.dart';

enum BusArrivalStatus { arriving, approaching, minutes, unknown }
class BusVehiclePosition extends Equatable {
  const BusVehiclePosition({
    required this.plate,
    required this.lat,
    required this.lon,
    required this.azimuth,
  });

  final String plate;
  final double lat;
  final double lon;
  final int azimuth;

  @override
  List<Object?> get props => [plate, lat, lon, azimuth];
}

class BusStopEtaViewModel extends Equatable {
  const BusStopEtaViewModel({
    required this.stopUid,
    required this.direction,
    required this.sequence,
    required this.estimateSeconds,
    required this.nextBusTime,
    required this.stopStatus,
    required this.vehiclePlates,
    this.arrivalUnix = 0,
    this.vehicles = const [],
  });

  final String stopUid;
  final int direction;
  final int sequence;
  final int estimateSeconds;
  final String nextBusTime;
  final int stopStatus;
  final List<String> vehiclePlates;
  final int arrivalUnix;
  final List<BusVehiclePosition> vehicles;

  int get estimateMinutes => etaCeilMinutes(estimateSeconds);
  /// Re-derives [estimateSeconds] from [arrivalUnix] against [now] so the
  /// displayed countdown decays between server frames. When [arrivalUnix] is 0
  /// the server-sent [estimateSeconds] is kept unchanged. Negatives clamp to 0
  /// so a just-passed arrival instant with stopStatus 0 still reads 進站中.
  BusStopEtaViewModel decayed(DateTime now) {
    if (arrivalUnix <= 0) return this;
    final seconds = arrivalUnix - now.millisecondsSinceEpoch ~/ 1000;
    return copyWith(estimateSeconds: seconds > 0 ? seconds : 0);
  }

  BusStopEtaViewModel copyWith({int? estimateSeconds}) => BusStopEtaViewModel(
    stopUid: stopUid,
    direction: direction,
    sequence: sequence,
    estimateSeconds: estimateSeconds ?? this.estimateSeconds,
    nextBusTime: nextBusTime,
    stopStatus: stopStatus,
    vehiclePlates: vehiclePlates,
    arrivalUnix: arrivalUnix,
    vehicles: vehicles,
  );

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
    arrivalUnix,
    vehicles,
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
