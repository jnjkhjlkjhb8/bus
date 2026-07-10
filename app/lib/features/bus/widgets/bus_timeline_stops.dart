/// Pure derivation of the horizontal route timeline's stop list from static
/// stops plus live ETA, split out of `bus_route_screen.dart` so it is unit
/// testable without pumping the widget tree. Behavior mirrors the screen
/// exactly; the display invariants (ETA ceil-to-minutes, one status-code
/// mapping) live in `eta_format.dart` and are reused here, not re-implemented.
library;

import 'package:wheres_the_car/core/firebase/remote_config.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/eta_format.dart';
import 'package:wheres_the_car/data/models/timeline_stop.dart';

/// Live per-stop state for the timeline. 進站中 (arriving) is reserved for a
/// live bus at the stop — the one status the crude [_approaching] threshold
/// can't express — so it routes through the shared [busStopDisplayStatus]
/// mapping; everything within the approaching window stays 即將進站.
TimelineStopState timelineStopState(BusStopEtaViewModel? eta) {
  if (eta == null) return TimelineStopState.none;
  final status = busStopDisplayStatus(
    estimateSeconds: eta.estimateSeconds,
    stopStatus: eta.stopStatus,
  );
  if (status == BusStopDisplayStatus.arriving) {
    return TimelineStopState.arriving;
  }
  return _approaching(eta)
      ? TimelineStopState.approaching
      : TimelineStopState.none;
}

bool _approaching(BusStopEtaViewModel? eta) {
  if (eta == null) return false;
  return eta.estimateSeconds > 0 &&
      eta.estimateSeconds <= AppConfig.getInt('eta_approaching_threshold_s');
}

/// Per-stop fare section for two-section (兩段票) routes: stops before the
/// buffer zone are section 1, stops after are section 2, buffer stops carry the
/// section they lead into. Returns an empty map for any other pricing (flat,
/// free, 里程計費) so the timeline draws no section band. [pricingType] is the
/// route's TDX fare pricing type (2 = 兩段票).
///
/// Assumes a single contiguous buffer zone (the 兩段票 norm). A route with
/// multiple buffer zones would collapse to two sections; revisit if TDX ever
/// ships 3+ sections on one direction.
Map<int, int> fareSectionsBySequence({
  required List<BusStopModel> stops,
  required Set<int> bufferSequences,
  required int pricingType,
}) {
  if (bufferSequences.isEmpty || pricingType != 2) return const {};
  final lastBuffer = bufferSequences.reduce((a, b) => a > b ? a : b);
  // Only stops past the buffer zone are section 2; buffer stops and everything
  // before them read as section 1 (buffer cells are flagged separately).
  return {
    for (final st in stops) st.sequence: st.sequence > lastBuffer ? 2 : 1,
  };
}

/// Derives the ordered timeline-stop list for one direction from the static
/// [stops] and the live [etaMap]. Each stop's ETA is looked up first by
/// direction+sequence (`seq:<direction>:<sequence>`) then by uid
/// (`uid:<stopUid>`); a stop with no ETA entry is still emitted, with no
/// primary time and a [TimelineStopState.none] state.
List<TimelineStop> deriveTimelineStops({
  required List<BusStopModel> stops,
  required Map<String, BusStopEtaViewModel> etaMap,
  required int direction,
  required Set<int> bufferSequences,
  required int pricingType,
}) {
  BusStopEtaViewModel? etaFor(BusStopModel stop) =>
      etaMap['seq:$direction:${stop.sequence}'] ??
      etaMap['uid:${stop.stopUid}'];
  final sections = fareSectionsBySequence(
    stops: stops,
    bufferSequences: bufferSequences,
    pricingType: pricingType,
  );
  return [
    for (final st in stops)
      if (etaFor(st) case final eta)
        TimelineStop(
          uid: st.stopUid,
          name: st.stopName,
          primaryTime: eta?.displayLabel,
          state: timelineStopState(eta),
          isBuffer: bufferSequences.contains(st.sequence),
          fareSection: sections[st.sequence],
        ),
  ];
}

/// Semantic ETA-label classes for a timeline stop, mirroring the horizontal
/// timeline's label ladder. [countdownSoon] is a 0/1/2-minute countdown, which
/// the timeline paints in the arriving color.
enum TimelineEtaLabel { arriving, approaching, countdown, countdownSoon, none }

/// Pure mapping from a derived [TimelineStop] to its ETA-label class. The
/// countdown text itself is [TimelineStop.primaryTime]; this only picks the
/// class the timeline styles it with.
TimelineEtaLabel timelineEtaLabel(TimelineStop stop) {
  if (stop.state == TimelineStopState.arriving) {
    return TimelineEtaLabel.arriving;
  }
  if (stop.state == TimelineStopState.approaching) {
    return TimelineEtaLabel.approaching;
  }
  final primary = stop.primaryTime;
  if (primary == null) return TimelineEtaLabel.none;
  if (primary == '0' || primary == '1' || primary == '2') {
    return TimelineEtaLabel.countdownSoon;
  }
  return TimelineEtaLabel.countdown;
}
