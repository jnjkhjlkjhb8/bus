part of '../view/bus_route_screen.dart';

const List<FontFeature> _tnum = AppTextStyles.tabularFigures;

typedef _BusVehicle = ({String afterStopUid, double progress, String plate});
typedef _DepartureInfo = ({String time, bool isNext});
typedef _TimetableInfo = ({String time, bool lowFloor, bool isNext});

String? _etaLabel(BusStopEtaViewModel? eta) {
  if (eta == null) return null;
  return eta.displayLabel;
}

bool _approaching(BusStopEtaViewModel? eta) {
  if (eta == null) return false;
  return eta.estimateSeconds > 0 &&
      eta.estimateSeconds <= AppConfig.getInt('eta_approaching_threshold_s');
}

/// Live per-stop state for the timeline. 進站中 (arriving) is reserved for a
/// live bus at the stop — the one status the crude [_approaching] threshold
/// can't express — so it routes through the shared [busStopDisplayStatus]
/// mapping; everything within the approaching window stays 即將進站.
TimelineStopState _stopState(BusStopEtaViewModel? eta) {
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

/// Per-stop fare section for two-section (兩段票) routes: stops before the
/// buffer zone are section 1, stops after are section 2, buffer stops carry the
/// section they lead into. Returns an empty map for any other pricing (flat,
/// free, 里程計費) so the timeline draws no section band.
///
/// ponytail: assumes a single contiguous buffer zone (the 兩段票 norm). A route
/// with multiple buffer zones would collapse to two sections; revisit if TDX
/// ever ships 3+ sections on one direction.
Map<int, int> _fareSectionsBySequence(BusRouteState s) {
  final buffers = s.bufferSequences;
  if (buffers.isEmpty || (s.fare?.pricingType ?? 0) != 2) return const {};
  final lastBuffer = buffers.reduce((a, b) => a > b ? a : b);
  final stops = s.direction == 0 ? s.route?.stopsGo : s.route?.stopsReturn;
  if (stops == null) return const {};
  // Only stops past the buffer zone are section 2; buffer stops and everything
  // before them read as section 1 (buffer cells are flagged separately).
  return {
    for (final st in stops) st.sequence: st.sequence > lastBuffer ? 2 : 1,
  };
}

String _markerEta(BusStopEtaViewModel? eta) {
  if (eta == null) return '–';
  final status = busStopDisplayStatus(
    estimateSeconds: eta.estimateSeconds,
    stopStatus: eta.stopStatus,
  );
  if (status == BusStopDisplayStatus.arriving) return '即';
  if (eta.estimateSeconds > 0) return '${eta.estimateMinutes}';
  return '–';
}

/// A not-yet-departed stop whose arrival is a scheduled clock time — the map
/// marker shows a clock icon instead of a countdown number.
bool _markerIsScheduled(BusStopEtaViewModel? eta) =>
    eta != null && eta.stopStatus == 1 && eta.nextBusTime.isNotEmpty;

List<BusVehiclePosition> _vehiclePositionsFor(BusRouteState s) {
  final byPlate = <String, BusVehiclePosition>{};
  for (final eta in s.etaMap.values) {
    if (eta.direction != s.direction) continue;
    for (final v in eta.vehicles) {
      byPlate[v.plate] = v;
    }
  }
  return byPlate.values.toList();
}

LatLngBounds _boundsOf(List<LatLng> pts) {
  var minLat = pts.first.latitude;
  var maxLat = pts.first.latitude;
  var minLng = pts.first.longitude;
  var maxLng = pts.first.longitude;
  for (final p in pts) {
    minLat = p.latitude < minLat ? p.latitude : minLat;
    maxLat = p.latitude > maxLat ? p.latitude : maxLat;
    minLng = p.longitude < minLng ? p.longitude : minLng;
    maxLng = p.longitude > maxLng ? p.longitude : maxLng;
  }
  return LatLngBounds(
    southwest: LatLng(minLat, minLng),
    northeast: LatLng(maxLat, maxLng),
  );
}

// Memoize the timeline-stop derivation per state instance so both eta-scoped
// selectors (timeline + stop list) share one computation instead of rebuilding
// the list once per widget rebuild.
final Expando<List<TimelineStop>> _stopsCache = Expando('busRouteStops');

List<TimelineStop> _stopsFor(BusRouteState s) {
  final cached = _stopsCache[s];
  if (cached != null) return cached;
  final derived = _deriveStops(s);
  _stopsCache[s] = derived;
  return derived;
}

List<TimelineStop> _deriveStops(BusRouteState s) {
  final stops = s.direction == 0 ? s.route?.stopsGo : s.route?.stopsReturn;
  if (stops == null) return const [];
  BusStopEtaViewModel? etaFor(BusStopModel stop) =>
      s.etaMap['seq:${s.direction}:${stop.sequence}'] ??
      s.etaMap['uid:${stop.stopUid}'];
  final sections = _fareSectionsBySequence(s);
  return [
    for (final st in stops)
      if (etaFor(st) case final eta)
        TimelineStop(
          uid: st.stopUid,
          name: st.stopName,
          primaryTime: _etaLabel(eta),
          state: _stopState(eta),
          isBuffer: s.bufferSequences.contains(st.sequence),
          fareSection: sections[st.sequence],
        ),
  ];
}

String _timeLabel(String value) {
  if (value.length >= 5) return value.substring(0, 5);
  return value;
}

List<_DepartureInfo> _departuresFor(BusRouteState state) {
  final trips =
      state.daily?.tripsForDirection(state.direction) ?? const <BusDailyTrip>[];
  final now = TimeOfDay.now();
  final rows = <String>[];
  for (final trip in trips) {
    if (trip.stopTimes.isEmpty) continue;
    final first = trip.stopTimes.reduce(
      (a, b) => a.stopSequence <= b.stopSequence ? a : b,
    );
    final time = first.departureTime.isNotEmpty
        ? first.departureTime
        : first.arrivalTime;
    if (time.isNotEmpty) rows.add(_timeLabel(time));
  }
  rows.sort();
  final nextIndex = rows.indexWhere((t) => _isUpcoming(t, now));
  return [
    for (final (i, time) in rows.take(12).indexed)
      (time: time, isNext: i == (nextIndex < 0 ? 0 : nextIndex)),
  ];
}

// The next-departure highlight marks the first trip whose clock time has not
// yet passed. Returns false once the day's service is over, so nothing is
// highlighted rather than defaulting to the first (past) trip.
bool _isUpcoming(String hhmm, TimeOfDay now) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return false;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return false;
  return h > now.hour || (h == now.hour && m >= now.minute);
}

/// Headsign for the current direction, shown once above the timetable board.
String _headsignFor(BusRouteState state) => state.currentHeadsign.isNotEmpty
    ? state.currentHeadsign
    : (state.currentStops.isEmpty ? '-' : state.currentStops.last.stopName);

List<_TimetableInfo> _timetableFor(BusRouteState state) {
  final trips =
      state.daily?.tripsForDirection(state.direction) ?? const <BusDailyTrip>[];
  final now = TimeOfDay.now();
  final raw = <(String, bool)>[];
  for (final trip in trips.take(24)) {
    if (trip.stopTimes.isEmpty) continue;
    final first = trip.stopTimes.reduce(
      (a, b) => a.stopSequence <= b.stopSequence ? a : b,
    );
    final time = first.departureTime.isNotEmpty
        ? first.departureTime
        : first.arrivalTime;
    if (time.isEmpty) continue;
    raw.add((_timeLabel(time), trip.isLowFloor));
  }
  raw.sort((a, b) => a.$1.compareTo(b.$1));
  final nextIndex = raw.indexWhere((r) => _isUpcoming(r.$1, now));
  return [
    for (final (i, r) in raw.indexed)
      (time: r.$1, lowFloor: r.$2, isNext: i == nextIndex),
  ];
}

String _farePricingTypeLabel(int type) {
  return switch (type) {
    0 => '未知',
    1 => '一段票',
    2 => '兩段票',
    3 => '里程計費',
    _ => '類型 $type',
  };
}
