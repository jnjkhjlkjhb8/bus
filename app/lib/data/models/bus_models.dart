import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/data/generated/bus.pb.dart';

enum BusArrivalStatus { arriving, approaching, minutes, unknown }

String? _clockLabel(String value) {
  if (value.isEmpty) return null;
  final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(value);
  if (match != null) {
    final h = match.group(1)!.padLeft(2, '0');
    return '$h:${match.group(2)!}';
  }
  final parsed = DateTime.tryParse(value);
  if (parsed != null) {
    final local = parsed.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
  return null;
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
  });

  final String stopUid;
  final int direction;
  final int sequence;
  final int estimateSeconds;
  final String nextBusTime;
  final int stopStatus;
  final List<String> vehiclePlates;

  int get estimateMinutes =>
      estimateSeconds > 0 ? (estimateSeconds / 60).ceil() : 0;

  String? get displayLabel {
    if (estimateSeconds > 0) return '$estimateMinutes分';
    if (stopStatus == 0 && estimateSeconds == 0) return '進站中';
    return _clockLabel(nextBusTime) ??
        switch (stopStatus) {
          1 => '尚未發車',
          2 => '交管不停靠',
          3 => '末班已過',
          4 => '今日未營運',
          _ => null,
        };
  }

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
  final Bus_Fare? fare;

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
