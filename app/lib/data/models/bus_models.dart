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
    return copyWith(
      estimateSeconds: etaRemainingSeconds(
        arrivalUnix: arrivalUnix,
        serverEstimateSeconds: estimateSeconds,
        now: now,
      ),
    );
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

enum BusArrivalState { arriving, scheduled, unknown }

/// The one stop-arrival state mapping, shared by decode and local decay.
BusArrivalState busArrivalStateFor(int stopStatus, int? minutes) =>
    switch (stopStatus) {
      0 when minutes != null => BusArrivalState.scheduled,
      1 => BusArrivalState.arriving,
      _ => BusArrivalState.unknown,
    };

/// A member stop of a station group, resolved to the fields the stop screen
/// reads. A validated domain type: no proto leaks past the decoder.
class BusStationMember {
  const BusStationMember({
    required this.stationUid,
    required this.stationId,
    required this.stationName,
    required this.lat,
    required this.lon,
  });

  final String stationUid;
  final String stationId;
  final String stationName;
  final double lat;
  final double lon;
}

/// One route's arrival at a stop. [minutes] and [state] are derived from
/// [arrivalUnix] against wall-clock time; [decayed] re-derives them locally so
/// the countdown stays accurate between server frames.
class BusStopArrival {
  const BusStopArrival({
    required this.stationId,
    required this.routeName,
    required this.destination,
    required this.state,
    this.minutes,
    this.stopStatus = 0,
    this.arrivalUnix = 0,
  });

  final String stationId;
  final String routeName;
  final String destination;
  final BusArrivalState state;
  final int? minutes;

  /// TDX StopStatus, kept so [decayed] can re-derive [state] locally.
  final int stopStatus;

  /// Absolute arrival instant (Unix seconds), or 0 when the server sent none.
  final int arrivalUnix;

  /// Re-derives [minutes] and [state] from [arrivalUnix] against [now] so the
  /// countdown decays between server pushes. Leaves the arrival unchanged when
  /// no absolute instant was sent.
  BusStopArrival decayed(DateTime now) {
    if (arrivalUnix <= 0) return this;
    final seconds = etaRemainingSeconds(
      arrivalUnix: arrivalUnix,
      serverEstimateSeconds: 0,
      now: now,
    );
    final mins = seconds > 0 ? etaCeilMinutes(seconds) : null;
    return BusStopArrival(
      stationId: stationId,
      routeName: routeName,
      destination: destination,
      state: busArrivalStateFor(stopStatus, mins),
      minutes: mins,
      stopStatus: stopStatus,
      arrivalUnix: arrivalUnix,
    );
  }
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
