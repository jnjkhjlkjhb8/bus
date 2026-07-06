import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';

enum JourneyLegKind { bus, metro, tra, thsr, other }

JourneyLegKind _kindOf(PlanSection s) => switch (s.identity.routeType) {
  'bus' => JourneyLegKind.bus,
  'mrt' => JourneyLegKind.metro,
  'tra' => JourneyLegKind.tra,
  'thsr' => JourneyLegKind.thsr,
  _ => switch (s.transport.mode) {
    'bus' => JourneyLegKind.bus,
    'subway' || 'metro' => JourneyLegKind.metro,
    'train' || 'rail' => JourneyLegKind.tra,
    'highSpeedTrain' => JourneyLegKind.thsr,
    _ => JourneyLegKind.other,
  },
};

/// One transit leg of a navigation session. Leading walk sections are folded
/// into the following transit leg (walkers see 「步行至X」 inside the waiting
/// card, matching the Google Maps pattern) so the session state machine only
/// ever points at a transit leg.
class JourneyLeg extends Equatable {
  const JourneyLeg({
    required this.kind,
    required this.routeLabel,
    required this.boardStop,
    required this.alightStop,
    required this.stopNames,
    required this.identity,
    required this.leadingWalkMinutes,
    required this.scheduledDeparture,
    required this.scheduledArrival,
    required this.boardLocation,
    required this.stopLocations,
  });

  static List<JourneyLeg> legsFromRoute(PlanRoute route) {
    final legs = <JourneyLeg>[];
    var pendingWalkSeconds = 0;
    for (final section in route.sections) {
      if (section.type != 'transit') {
        pendingWalkSeconds += section.travelSummary.duration;
        continue;
      }
      final headsign = section.transport.headsign;
      final label = section.transport.shortName.isEmpty
          ? section.transport.name
          : section.transport.shortName;
      legs.add(
        JourneyLeg(
          kind: _kindOf(section),
          routeLabel: headsign.isEmpty ? label : '$label 往$headsign',
          boardStop: section.departure.name,
          alightStop: section.arrival.name,
          stopNames: [for (final s in section.intermediateStops) s.name],
          identity: section.identity,
          leadingWalkMinutes: (pendingWalkSeconds / 60).ceil(),
          scheduledDeparture: DateTime.tryParse(section.departure.time),
          scheduledArrival: DateTime.tryParse(section.arrival.time),
          boardLocation: section.departure.location,
          stopLocations: [
            for (final s in section.intermediateStops) s.location,
            section.arrival.location,
          ],
        ),
      );
      pendingWalkSeconds = 0;
    }
    return legs;
  }

  final JourneyLegKind kind;
  final String routeLabel;
  final String boardStop;
  final String alightStop;
  final List<String> stopNames;
  final PlanIdentity identity;
  final int leadingWalkMinutes;
  final DateTime? scheduledDeparture;
  final DateTime? scheduledArrival;
  final PlanPoint boardLocation;

  /// Intermediate stop locations plus the arrival location, in travel order —
  /// used for riding-mode progress by nearest-upcoming-stop.
  final List<PlanPoint> stopLocations;

  @override
  List<Object?> get props => [
    kind,
    routeLabel,
    boardStop,
    alightStop,
    stopNames,
    identity,
    leadingWalkMinutes,
    scheduledDeparture,
    scheduledArrival,
    boardLocation,
    stopLocations,
  ];
}
