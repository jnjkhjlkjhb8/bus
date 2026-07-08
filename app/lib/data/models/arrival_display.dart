import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/eta_format.dart';
import 'package:wheres_the_car/data/models/eta_status.dart';

/// The small contract the shared arrival tile renders (CONTEXT.md: "arrival
/// display"). Each transit mode maps its own domain model to it; the tile owns
/// the rendering invariants (mono time values via `EtaValue`, the static
/// coming-soon highlight). This value carries only what the tile needs:
///
/// - [label]: the primary identifier text (bus route number, metro line/route).
/// - [destination]: the "往 X" terminal.
/// - [status]: the unified [EtaStatus] driving the time column and its colour.
/// - [rank]: the sort key; soonest first, service-state rows last. The
///   coming-soon highlight applies to the rank-0 row when [rank] <= 3 (see
///   [isComingSoon]).
///
/// The status-and-rank *rules* stay in eta_format.dart, applied by the mode
/// mappers below — this class does not re-derive them.
class ArrivalDisplay {
  const ArrivalDisplay({
    required this.label,
    required this.destination,
    required this.status,
    required this.rank,
  });

  /// Maps a bus stop arrival to its display, reproducing the one status/rank
  /// mapping the bus stop sheet used: 進站中 first, 即將進站 next, then minutes
  /// (later minutes rank later), and every service-state row (尚未發車 / 末班已過
  /// / 交管不停靠 / scheduled clock time) last.
  factory ArrivalDisplay.fromBusStop(BusStopArrival a) {
    final (EtaStatus status, int rank) = switch (a.displayStatus) {
      BusStopDisplayStatus.arriving => (EtaStatus.arriving(), 0),
      BusStopDisplayStatus.departingSoon => (EtaStatus.approaching(), 1),
      BusStopDisplayStatus.minutes => (
        EtaStatus.minutes(a.minutes ?? 0),
        (a.minutes ?? 0) + 2,
      ),
      _ => (
        a.displayLabel != null
            ? EtaStatus.label(a.displayLabel!)
            : EtaStatus.unknown(),
        9999,
      ),
    };
    return ArrivalDisplay(
      label: a.routeName,
      destination: a.destination,
      status: status,
      rank: rank,
    );
  }

  /// Maps a metro arrival to its display: an approaching train shows 即將進站,
  /// otherwise the minute countdown. [rank] is the minute estimate so the row
  /// order matches the feed's estimate sort. Metro does not surface the
  /// coming-soon highlight, so callers leave it off regardless of [rank].
  factory ArrivalDisplay.fromMetro({
    required String line,
    required String destination,
    required int estimateMinutes,
    required bool approaching,
  }) => ArrivalDisplay(
    label: line,
    destination: destination,
    status: approaching
        ? EtaStatus.approaching()
        : EtaStatus.minutes(estimateMinutes),
    rank: estimateMinutes,
  );

  final String label;
  final String destination;
  final EtaStatus status;
  final int rank;

  /// Whether this arrival is eligible for the coming-soon highlight: only the
  /// soonest ranked row (rank <= 3) qualifies. The caller pairs this with the
  /// list position so at most the first row is highlighted.
  bool get isComingSoon => rank <= 3;
}
