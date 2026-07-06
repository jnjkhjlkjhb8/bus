part of '../view/bus_route_screen.dart';

const List<FontFeature> _tnum = AppTextStyles.tabularFigures;

typedef _BusVehicle = ({String afterStopUid, double progress, String plate});
typedef _DepartureInfo = ({String time, bool isNext});
typedef _TimetableInfo = ({
  String destination,
  String time,
  String trip,
  String vehicle,
});

String? _etaLabel(BusStopEtaViewModel? eta) {
  if (eta == null) return null;
  return eta.displayLabel;
}

bool _approaching(BusStopEtaViewModel? eta) {
  if (eta == null) return false;
  return eta.estimateSeconds > 0 &&
      eta.estimateSeconds <= AppConfig.getInt('eta_approaching_threshold_s');
}

String _markerEta(BusStopEtaViewModel? eta) {
  if (eta == null) return '–';
  if (eta.estimateSeconds > 0) return '${eta.estimateMinutes}';
  final status = busStopDisplayStatus(
    estimateSeconds: eta.estimateSeconds,
    stopStatus: eta.stopStatus,
  );
  return status == BusStopDisplayStatus.arriving ? '即' : '–';
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

List<TimelineStop> _stopsFor(BusRouteState s) {
  final stops = s.direction == 0 ? s.route?.stopsGo : s.route?.stopsReturn;
  if (stops == null) return const [];
  BusStopEtaViewModel? etaFor(BusStopModel stop) =>
      s.etaMap['seq:${s.direction}:${stop.sequence}'] ??
      s.etaMap['uid:${stop.stopUid}'];
  return [
    for (final st in stops)
      TimelineStop(
        uid: st.stopUid,
        name: st.stopName,
        primaryTime: _etaLabel(etaFor(st)),
        state: _approaching(etaFor(st))
            ? TimelineStopState.approaching
            : TimelineStopState.none,
        isBuffer: s.bufferSequences.contains(st.sequence),
      ),
  ];
}

String _timeLabel(String value) {
  if (value.length >= 5) return value.substring(0, 5);
  return value;
}

List<_DepartureInfo> _departuresFor(BusRouteState state) {
  final trips =
      state.daily?.tripsForDirection(state.direction) ??
      const <BusDailyTrip>[];
  final now = TimeOfDay.now();
  final rows = <String>[];
  for (final trip in trips) {
    if (trip.stopTimes.isEmpty) continue;
    final first = trip.stopTimes.reduce(
      (a, b) =>
          a.stopSequence <= b.stopSequence ? a : b,
    );
    final time = first.departureTime.isNotEmpty
        ? first.departureTime
        : first.arrivalTime;
    if (time.isNotEmpty) rows.add(_timeLabel(time));
  }
  rows.sort();
  final nextIndex = rows.indexWhere((t) {
    final parts = t.split(':');
    if (parts.length < 2) return false;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return false;
    return h > now.hour || (h == now.hour && m >= now.minute);
  });
  return [
    for (final (i, time) in rows.take(12).indexed)
      (time: time, isNext: i == (nextIndex < 0 ? 0 : nextIndex)),
  ];
}

List<_TimetableInfo> _timetableFor(BusRouteState state) {
  final trips =
      state.daily?.tripsForDirection(state.direction) ??
      const <BusDailyTrip>[];
  final destination = state.currentHeadsign.isNotEmpty
      ? state.currentHeadsign
      : (state.currentStops.isEmpty ? '-' : state.currentStops.last.stopName);
  final rows = <_TimetableInfo>[];
  for (final trip in trips.take(24)) {
    if (trip.stopTimes.isEmpty) continue;
    final first = trip.stopTimes.reduce(
      (a, b) =>
          a.stopSequence <= b.stopSequence ? a : b,
    );
    final time = first.departureTime.isNotEmpty
        ? first.departureTime
        : first.arrivalTime;
    rows.add((
      destination: destination,
      time: _timeLabel(time),
      trip: trip.tripId.isEmpty ? '-' : trip.tripId,
      vehicle: trip.isLowFloor ? '低地板' : '-',
    ));
  }
  rows.sort((a, b) => a.time.compareTo(b.time));
  return rows;
}

List<(String, String)> _fareRows(BusFareInfo? fare) {
  if (fare == null) return const [];
  final rows = <(String, String)>[
    ('票價型態', _farePricingTypeLabel(fare.pricingType)),
    ('免費公車', fare.isFreeBus ? '是' : '否'),
  ];
  if (fare.sectionFaresJson.isNotEmpty) {
    rows.add(('分段票價', _farePayloadLabel(fare.sectionFaresJson)));
  }
  if (fare.stageFaresJson.isNotEmpty) {
    rows.add(('段次票價', _farePayloadLabel(fare.stageFaresJson)));
  }
  if (fare.odFaresJson.isNotEmpty) {
    rows.add(('起迄票價', _farePayloadLabel(fare.odFaresJson)));
  }
  return rows;
}

String _farePayloadLabel(List<int> data) {
  try {
    final parsed = jsonDecode(utf8.decode(data));
    if (parsed is Map) return '${parsed.length} 筆';
    if (parsed is List) return '${parsed.length} 筆';
  } on Object catch (_) {}
  return '已提供';
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
