import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/data/generated/maas.pb.dart' as maas;

class PlanResult extends Equatable {
  const PlanResult({required this.routes});

  factory PlanResult.fromProto(maas.MaasPlanResponse proto) => PlanResult(
    routes: [for (final route in proto.routes) PlanRoute.fromProto(route)],
  );

  final List<PlanRoute> routes;

  @override
  List<Object?> get props => [routes];
}

class PlanRoute extends Equatable {
  const PlanRoute({
    required this.travelTime,
    required this.startTime,
    required this.endTime,
    required this.transfers,
    required this.sections,
  });

  factory PlanRoute.fromProto(maas.Route proto) => PlanRoute(
    travelTime: proto.travelTime.toInt(),
    startTime: proto.startTime,
    endTime: proto.endTime,
    transfers: proto.transfers,
    sections: [
      for (final section in proto.sections) PlanSection.fromProto(section),
    ],
  );

  final int travelTime;
  final String startTime;
  final String endTime;
  final int transfers;
  final List<PlanSection> sections;

  PlanPoint? firstPoint({int leg = 0}) {
    if (leg >= sections.length) return null;
    final loc = sections[leg].departure.location;
    if (loc.lat == 0 && loc.lng == 0) return null;
    return loc;
  }

  List<PlanPoint> get points {
    final pts = <PlanPoint>[];
    for (final section in sections) {
      void add(PlanPoint point) {
        if (point.lat != 0 || point.lng != 0) pts.add(point);
      }

      add(section.departure.location);
      for (final stop in section.intermediateStops) {
        add(stop.location);
      }
      add(section.arrival.location);
    }
    return pts;
  }

  @override
  List<Object?> get props => [
    travelTime,
    startTime,
    endTime,
    transfers,
    sections,
  ];
}

class PlanSection extends Equatable {
  const PlanSection({
    required this.type,
    required this.travelSummary,
    required this.departure,
    required this.arrival,
    required this.transport,
    required this.intermediateStops,
    this.identity = const PlanIdentity.empty(),
  });

  factory PlanSection.fromProto(maas.Section proto) => PlanSection(
    type: proto.type,
    travelSummary: PlanTravelSummary.fromProto(proto.travelSummary),
    departure: PlanPlace.fromProto(proto.departure),
    arrival: PlanPlace.fromProto(proto.arrival),
    transport: PlanTransport.fromProto(proto.transport),
    intermediateStops: [
      for (final stop in proto.intermediateStops) PlanStop.fromProto(stop),
    ],
    identity: PlanIdentity.fromProto(proto.notificationIdentity),
  );

  final String type;
  final PlanTravelSummary travelSummary;
  final PlanPlace departure;
  final PlanPlace arrival;
  final PlanTransport transport;
  final List<PlanStop> intermediateStops;
  final PlanIdentity identity;

  @override
  List<Object?> get props => [
    type,
    travelSummary,
    departure,
    arrival,
    transport,
    intermediateStops,
    identity,
  ];
}

class PlanIdentity extends Equatable {
  const PlanIdentity({
    required this.routeType,
    required this.routeKey,
    required this.direction,
    required this.departureStopKey,
    required this.arrivalStopKey,
    required this.supported,
  });

  const PlanIdentity.empty()
    : routeType = '',
      routeKey = '',
      direction = '',
      departureStopKey = '',
      arrivalStopKey = '',
      supported = false;

  factory PlanIdentity.fromProto(maas.NotificationIdentity proto) =>
      PlanIdentity(
        routeType: proto.routeType,
        routeKey: proto.routeKey,
        direction: proto.direction,
        departureStopKey: proto.departureStopKey,
        arrivalStopKey: proto.arrivalStopKey,
        supported: proto.supported,
      );

  final String routeType;
  final String routeKey;
  final String direction;
  final String departureStopKey;
  final String arrivalStopKey;
  final bool supported;

  @override
  List<Object?> get props => [
    routeType,
    routeKey,
    direction,
    departureStopKey,
    arrivalStopKey,
    supported,
  ];
}

class PlanTravelSummary extends Equatable {
  const PlanTravelSummary({required this.duration, required this.length});

  factory PlanTravelSummary.fromProto(maas.Summary proto) => PlanTravelSummary(
    duration: proto.duration.toInt(),
    length: proto.length,
  );

  final int duration;
  final double length;

  @override
  List<Object?> get props => [duration, length];
}

class PlanPlace extends Equatable {
  const PlanPlace({
    required this.name,
    required this.type,
    required this.location,
    required this.time,
  });

  factory PlanPlace.fromProto(maas.Place proto) => PlanPlace(
    name: proto.name,
    type: proto.type,
    location: PlanPoint.fromProto(proto.location),
    time: proto.time,
  );

  final String name;
  final String type;
  final PlanPoint location;
  final String time;

  @override
  List<Object?> get props => [name, type, location, time];
}

class PlanPoint extends Equatable {
  const PlanPoint({required this.lat, required this.lng});

  factory PlanPoint.fromProto(maas.Location proto) =>
      PlanPoint(lat: proto.lat, lng: proto.lng);

  final double lat;
  final double lng;

  @override
  List<Object?> get props => [lat, lng];
}

class PlanTransport extends Equatable {
  const PlanTransport({
    required this.mode,
    required this.name,
    required this.shortName,
    required this.longName,
    required this.headsign,
    required this.category,
    required this.routeColor,
  });

  factory PlanTransport.fromProto(maas.Transport proto) => PlanTransport(
    mode: proto.mode,
    name: proto.name,
    shortName: proto.shortName,
    longName: proto.longName,
    headsign: proto.headsign,
    category: proto.category,
    routeColor: proto.routeColor,
  );

  final String mode;
  final String name;
  final String shortName;
  final String longName;
  final String headsign;
  final String category;
  final String routeColor;

  @override
  List<Object?> get props => [
    mode,
    name,
    shortName,
    longName,
    headsign,
    category,
    routeColor,
  ];
}

class PlanStop extends Equatable {
  const PlanStop({
    required this.name,
    required this.location,
    required this.departureTime,
  });

  factory PlanStop.fromProto(maas.IntermediateStop proto) => PlanStop(
    name: proto.name,
    location: PlanPoint.fromProto(proto.location),
    departureTime: proto.departureTime,
  );

  final String name;
  final PlanPoint location;
  final String departureTime;

  @override
  List<Object?> get props => [name, location, departureTime];
}
