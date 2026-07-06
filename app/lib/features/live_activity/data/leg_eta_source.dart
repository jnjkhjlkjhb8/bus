import 'package:wheres_the_car/data/repositories/bus_stop_eta_repository.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

typedef LegEtaStream = Stream<Duration?> Function(JourneyLeg leg);

/// Live ETA for bus legs whose notification identity resolved; every other
/// leg counts down from its scheduled departure.
// ponytail: metro/rail use scheduled countdown for now — switch to live
// sources once the planner emits supported identities for them.
Stream<Duration?> defaultLegEtaStream(JourneyLeg leg) {
  if (leg.kind == JourneyLegKind.bus && leg.identity.supported) {
    return BusStopEtaRepository.instance
        .watchStop(leg.identity.departureStopKey)
        .map((arrivals) {
          for (final a in arrivals) {
            if (leg.routeLabel.startsWith(a.routeName) &&
                a.minutes != null) {
              return Duration(minutes: a.minutes!);
            }
            if (leg.routeLabel.startsWith(a.routeName) &&
                a.state == BusArrivalState.arriving) {
              return Duration.zero;
            }
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
