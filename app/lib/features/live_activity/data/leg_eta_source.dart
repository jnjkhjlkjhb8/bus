import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/repositories/bus_repository.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

typedef LegEtaStream = Stream<Duration?> Function(JourneyLeg leg);

typedef RouteEtaStream =
    Stream<List<BusStopEtaViewModel>> Function(String routeKey);

/// Live per-stop ETA/vehicle stream for a route, used to track a pinned
/// vehicle's stop-by-stop progress toward the alight stop.
Stream<List<BusStopEtaViewModel>> defaultRouteEtaStream(String routeKey) =>
    BusRepository.instance.routeEta(routeKey);

/// Live ETA for bus legs whose notification identity resolved; every other
/// leg counts down from its scheduled departure. Non-bus legs will gain live
/// sources once the planner emits supported identities for them.
Stream<Duration?> defaultLegEtaStream(JourneyLeg leg) {
  final stopKey = leg.identity.departureStopKey;
  if (leg.kind == JourneyLegKind.bus &&
      leg.identity.supported &&
      stopKey.isNotEmpty) {
    return BusRepository.instance
        .stationEta('', stopKey)
        .map((arrivals) {
          for (final a in arrivals) {
            if (leg.routeLabel.startsWith(a.routeName) && a.minutes != null) {
              return Duration(minutes: a.minutes!);
            }
            if (leg.routeLabel.startsWith(a.routeName) && a.isArriving) {
              return Duration.zero;
            }
          }
          return null;
        });
  }
  // Synthetic identities from the in-app 追蹤 toggle (bus route screen) carry
  // the subroute uid in routeKey and the boarding stop uid in
  // departureStopKey; live ETA comes from the same stream the route screen
  // renders. stopStatus semantics follow eta_format.dart: only a live bus at
  // zero reads as arriving, positive seconds read as a countdown, everything
  // else is "no estimate".
  if (leg.kind == JourneyLegKind.bus &&
      leg.identity.routeKey.isNotEmpty &&
      stopKey.isNotEmpty) {
    return BusRepository.instance.routeEta(leg.identity.routeKey).map((etas) {
      for (final e in etas) {
        if (e.stopUid != stopKey) continue;
        if (leg.identity.direction.isNotEmpty &&
            '${e.direction}' != leg.identity.direction) {
          continue;
        }
        if (e.stopStatus == 0 && e.estimateSeconds == 0) return Duration.zero;
        if (e.estimateSeconds > 0) return Duration(seconds: e.estimateSeconds);
        return null;
      }
      return null;
    });
  }
  return scheduledCountdown(leg.scheduledDeparture);
}

/// Emits the remaining time until [departure] once per 30s, clamped at zero.
Stream<Duration?> scheduledCountdown(
  DateTime? departure, {
  Duration tick = const Duration(seconds: 30),
}) async* {
  if (departure == null) {
    yield null;
    return;
  }
  Duration remaining() {
    final d = departure.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  yield remaining();
  yield* Stream.periodic(tick, (_) => remaining());
}
