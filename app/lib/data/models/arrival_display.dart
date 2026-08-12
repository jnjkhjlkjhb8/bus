import 'package:wheres_the_bus/data/models/bus_models.dart';
import 'package:wheres_the_bus/data/models/eta_format.dart';
import 'package:wheres_the_bus/data/models/eta_status.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';

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
    this.crowdLevel = CrowdLevel.unknown,
    this.isLastBus = false,
  });

  /// Maps a bus stop arrival to its display, reproducing the one status/rank
  /// mapping the bus stop sheet used: 進站中 first, 即將進站 next, then minutes
  /// (later minutes rank later), and every service-state row (尚未發車 / 末班已過
  /// / 交管不停靠 / scheduled clock time) last.
  factory ArrivalDisplay.fromBusStop(AppI18n i18n, BusStopArrival a) {
    final label = a.displayLabelOf(i18n);
    final (EtaStatus status, int rank) = switch (a.displayStatus) {
      BusStopDisplayStatus.arriving => (EtaStatus.arriving(), 0),
      BusStopDisplayStatus.departingSoon => (EtaStatus.approaching(), 1),
      BusStopDisplayStatus.minutes => (
        EtaStatus.minutes(a.minutes ?? 0),
        (a.minutes ?? 0) + 2,
      ),
      // Not-yet-departed with a scheduled clock time (HH:mm): show the clock
      // but keep the time-based rank so it interleaves with live arrivals by
      // when it actually comes, instead of sinking to the service-state floor.
      BusStopDisplayStatus.notDeparted
          when label != null && a.minutes != null =>
        (
          EtaStatus.label(label),
          (a.minutes ?? 0) + 2,
        ),
      _ => (
        label != null ? EtaStatus.label(label) : EtaStatus.unknown(),
        9999,
      ),
    };
    return ArrivalDisplay(
      label: a.routeName,
      destination: a.destination,
      status: status,
      rank: rank,
      crowdLevel: a.crowdLevel,
      isLastBus: a.isLastBus,
    );
  }

  /// Maps a metro arrival to its display: a 分/秒 countdown, collapsing to 進站中
  /// once the estimate reaches zero. [rank] is the second estimate so the row
  /// order matches the feed's estimate sort. Metro does not surface the
  /// coming-soon highlight, so callers leave it off regardless of [rank].
  factory ArrivalDisplay.fromMetro({
    required String line,
    required String destination,
    required int estimateSeconds,
  }) => ArrivalDisplay(
    label: line,
    destination: destination,
    status: estimateSeconds <= 0
        ? EtaStatus.arriving()
        : EtaStatus.minutesSeconds(estimateSeconds ~/ 60, estimateSeconds % 60),
    rank: estimateSeconds,
  );

  final String label;
  final String destination;
  final EtaStatus status;
  final int rank;

  /// How full the vehicle this arrival describes is, resolved server-side from
  /// its plate. Only Taipei buses report it; metro and every other city leave
  /// it UNKNOWN, and nothing is drawn.
  final CrowdLevel crowdLevel;

  /// Whether the feed confirmed this is the route's last bus of the day (TDX
  /// IsLastBus). Only 公路總局 and the counties it manages report it; everywhere
  /// else it stays false and nothing is marked.
  final bool isLastBus;

  /// Whether this arrival is eligible for the coming-soon highlight: only the
  /// soonest ranked row (rank <= 3) qualifies. The caller pairs this with the
  /// list position so at most the first row is highlighted.
  bool get isComingSoon => rank <= 3;
}
