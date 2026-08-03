/// The 追蹤 session's construction and ownership seam (CONTEXT.md: 追蹤).
///
/// Starting a 追蹤 used to mean hand-building a thirteen-field [JourneyLeg] and
/// a six-field [PlanIdentity] at the call site: three bus-side sites and one
/// rail-side one did it, and two of them spelled out the same `routeLabel`
/// recipe independently. Recognising "is the running session mine?" was written
/// out twice more. Both now live here, so a surface starting a 追蹤 supplies
/// only what it actually knows.
///
/// A trackOnly leg is deliberately sparse. It never rides, so the riding
/// progress lists ([JourneyLeg.stopNames], [JourneyLeg.stopLocations]) stay
/// empty and [PlanIdentity.supported] is false: these identities are not
/// bookable plan sections, they are just enough to name one vehicle.
library;

import 'package:wheres_the_bus/data/models/bus_models.dart';
import 'package:wheres_the_bus/data/models/plan_models.dart';
import 'package:wheres_the_bus/data/tracking/journey_models.dart';
import 'package:wheres_the_bus/data/tracking/journey_session_state.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';

/// The route label a 追蹤 card shows: the route number, plus its headsign when
/// the feed publishes one. One recipe, because a bus tracked from the map and
/// the same bus tracked from the stop list must not read differently.
String busTrackingLabel({
  required String routeName,
  required String headsign,
}) => headsign.isEmpty ? routeName : '$routeName 往$headsign';

/// Builds the leg for a bus 追蹤 session counting down to [stops]\[boardIndex].
///
/// The 目標站 is that stop; [JourneyLeg.alightStop] carries the route's terminus
/// only so the card can name where the bus is ultimately headed.
JourneyLeg busTrackingLeg({
  required BusRouteViewModel route,
  required List<BusStopModel> stops,
  required int boardIndex,
  required int direction,
}) {
  final stop = stops[boardIndex];
  return JourneyLeg(
    kind: JourneyLegKind.bus,
    routeLabel: busTrackingLabel(
      routeName: route.routeName,
      headsign: direction == 0 ? route.headsignGo : route.headsignReturn,
    ),
    boardStop: stop.stopName,
    alightStop: stops.last.stopName,
    stopNames: const [],
    identity: PlanIdentity(
      routeType: 'bus',
      routeKey: route.subRouteUid,
      direction: '$direction',
      departureStopKey: stop.stopUid,
      arrivalStopKey: '',
      supported: false,
    ),
    leadingWalkMinutes: 0,
    scheduledDeparture: null,
    scheduledArrival: null,
    boardLocation: PlanPoint(lat: stop.lat, lng: stop.lon),
    stopLocations: const [],
  );
}

/// Builds the leg for a rail 追蹤 session from [boardName] to [alightName].
///
/// A trackOnly rail leg has no real O/D keys, so the identity borrows two
/// fields to carry the train's identity instead: `routeKey` is the train
/// number and `direction` is the service date. [isTrackingTrain] reads them
/// back — the two must agree, which is why both live in this file.
///
/// [delayMinutes] is folded into the scheduled departure so the countdown
/// reflects live 誤點, but deliberately not into [railSchedule]: the tracker
/// applies live delay to the schedule itself as it advances.
JourneyLeg railTrackingLeg({
  required AppI18n i18n,
  required bool isThsr,
  required String trainNo,
  required String trainLabel,
  required String serviceDate,
  required String boardName,
  required String alightName,
  required DateTime? scheduledDeparture,
  required DateTime? scheduledArrival,
  required int delayMinutes,
  required List<RailStopSchedule> railSchedule,
}) => JourneyLeg(
  kind: isThsr ? JourneyLegKind.thsr : JourneyLegKind.tra,
  routeLabel: i18n.railTrainTowards(trainLabel, trainNo, alightName),
  boardStop: boardName,
  alightStop: alightName,
  stopNames: const [],
  identity: PlanIdentity(
    routeType: isThsr ? 'thsr' : 'tra',
    routeKey: trainNo,
    direction: serviceDate,
    departureStopKey: '',
    arrivalStopKey: '',
    supported: false,
  ),
  leadingWalkMinutes: 0,
  scheduledDeparture: scheduledDeparture?.add(
    Duration(minutes: delayMinutes),
  ),
  scheduledArrival: scheduledArrival,
  boardLocation: const PlanPoint(lat: 0, lng: 0),
  stopLocations: const [],
  railSchedule: railSchedule,
);

/// The stop UID a bus 追蹤 is counting down to on [subRouteUid], or null.
///
/// Only a waiting trackOnly session on that very subroute counts: a navigation
/// session, or another route's session, must leave this route's toggles idle.
String? trackedBusStopUid(JourneySessionState state, String? subRouteUid) {
  final leg = _waitingTrackLeg(state);
  if (leg == null ||
      leg.kind != JourneyLegKind.bus ||
      subRouteUid == null ||
      leg.identity.routeKey != subRouteUid) {
    return null;
  }
  return leg.identity.departureStopKey;
}

/// Whether a rail 追蹤 is running for [trainNo] on [serviceDate].
///
/// Both must match: a train number repeats every service day, so the date is
/// what distinguishes today's 152 次 from tomorrow's.
bool isTrackingTrain(
  JourneySessionState state, {
  required String trainNo,
  required String serviceDate,
}) {
  final leg = _waitingTrackLeg(state);
  return leg != null &&
      (leg.kind == JourneyLegKind.tra || leg.kind == JourneyLegKind.thsr) &&
      leg.identity.routeKey == trainNo &&
      leg.identity.direction == serviceDate;
}

/// The leg of a running standalone 追蹤 that is still waiting to board, or null
/// for an idle session, a navigation session, or one already under way.
JourneyLeg? _waitingTrackLeg(JourneySessionState state) {
  if (!state.trackOnly || state.phase != JourneyPhase.waiting) return null;
  return state.currentLeg;
}
