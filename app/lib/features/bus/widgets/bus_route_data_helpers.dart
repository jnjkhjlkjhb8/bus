part of '../view/bus_route_screen.dart';

const List<FontFeature> _tnum = AppTextStyles.tabularFigures;

typedef _BusVehicle = ({String afterStopUid, double progress, String plate});
typedef _DepartureInfo = ({String time, bool isNext});

/// What a stop marker's plate says. 進站中 is spelled out rather than abbreviated
/// to 即: the plate turns into a pill for this one state precisely so the word
/// fits, and an abbreviation nobody has to decode is worth the extra width.
String _markerEta(AppI18n i18n, BusStopEtaViewModel? eta) {
  if (eta == null) return '–';
  final status = busStopDisplayStatus(
    estimateSeconds: eta.estimateSeconds,
    stopStatus: eta.stopStatus,
  );
  if (status == BusStopDisplayStatus.arriving) return i18n.etaArriving;
  if (eta.estimateSeconds > 0) return '${eta.estimateMinutes}';
  return '–';
}

/// A not-yet-departed stop whose arrival is a scheduled clock time — the map
/// marker shows a clock icon instead of a countdown number.
bool _markerIsScheduled(BusStopEtaViewModel? eta) =>
    eta != null && eta.stopStatus == 1 && eta.nextBusTime.isNotEmpty;

/// A stop whose service is over for the day (末班已過 / 今日未營運) — the map
/// marker shows a cross instead of a countdown, since nothing more is coming.
bool _markerIsEnded(BusStopEtaViewModel? eta) {
  if (eta == null) return false;
  final status = busStopDisplayStatus(
    estimateSeconds: eta.estimateSeconds,
    stopStatus: eta.stopStatus,
  );
  return status == BusStopDisplayStatus.lastBusPassed ||
      status == BusStopDisplayStatus.notOperating;
}

/// A stop with no reading at all — no live estimate and no scheduled time (a
/// missing ETA frame, or 交管 with nothing behind it). Tested against the raw
/// status rather than the rendered '–' so it keeps working in every locale.
bool _markerIsUnknown(BusStopEtaViewModel? eta) =>
    eta == null ||
    (eta.estimateSeconds <= 0 &&
        busStopDisplayStatus(
              estimateSeconds: eta.estimateSeconds,
              stopStatus: eta.stopStatus,
            ) !=
            BusStopDisplayStatus.arriving);

typedef _MarkerStyle = ({
  Color fill,
  Color content,
  Color? ring,
  double ringWidth,
  double height,
  String? text,
  IconData? glyph,
  bool pill,
  int zIndex,
});

/// The stop marker's whole state ladder, quietest to loudest: nothing more
/// today, a scheduled departure, no reading, a countdown, 即將進站, 進站中.
///
/// The escalation runs on fill before colour — at arm's length in sunlight the
/// eye reads a light/dark mass long before it reads a hue — so the plate goes
/// hollow, then washed, then solid. Shape moves only once, on the one state
/// whose content is a word rather than a number.
///
/// 即將進站 comes from [timelineStopState], the same derivation the sheet's
/// timeline uses, so the map and the timeline cannot disagree about which stop
/// the bus is nearly at.
_MarkerStyle _markerStyle(
  AppI18n i18n,
  BusStopEtaViewModel? eta,
  ColorScheme cs,
) {
  final isDark = cs.brightness == Brightness.dark;
  // Dark mode's plate can't stay white against the dark basemap, so it borrows
  // the elevated-surface pairing the app's other floating map chrome uses.
  final plate = isDark ? cs.surfaceContainerHigh : AppTheme.surfaceCardLight;
  // Recessive form shared by the three states that carry no live time. It used
  // to be a full-ink ring, which put the loudest marker on the least useful
  // fact — a stop whose last bus has gone shouted as loudly as one a minute
  // away.
  _MarkerStyle quiet({String? text, IconData? glyph}) => (
    fill: plate,
    content: cs.onSurfaceVariant,
    ring: cs.onSurfaceVariant,
    ringWidth: 1.5,
    height: 30,
    text: text,
    glyph: glyph,
    pill: false,
    zIndex: 0,
  );

  if (_markerIsEnded(eta)) return quiet(glyph: Icons.close_rounded);
  if (_markerIsScheduled(eta)) return quiet(glyph: Icons.schedule_rounded);
  if (_markerIsUnknown(eta)) return quiet(text: _markerEta(i18n, eta));

  final approach = isDark ? AppTheme.statusApproach : AppTheme.etaApproaching;
  return switch (timelineStopState(eta)) {
    TimelineStopState.arriving => (
      // Green, not red: an arriving bus is the moment to act, not an alarm
      // (docs/design.md). The light shade is the darker text-weight green,
      // because white sits on this fill and the badge green fails there.
      fill: isDark ? AppTheme.statusArriving : AppTheme.statusArrivingText,
      content: isDark ? AppTheme.inkLight : AppTheme.surfaceCardLight,
      ring: null,
      ringWidth: 0,
      height: 32,
      text: _markerEta(i18n, eta),
      glyph: null,
      pill: true,
      zIndex: 2,
    ),
    TimelineStopState.approaching => (
      // The wash is what makes this readable without reading: colour alone is
      // a hue change, colour plus a lighter body is a change in weight.
      fill: Color.alphaBlend(
        approach.withValues(alpha: isDark ? 0.14 : 0.10),
        plate,
      ),
      content: cs.onSurface,
      ring: approach,
      ringWidth: 3,
      height: 34,
      text: _markerEta(i18n, eta),
      glyph: null,
      pill: false,
      zIndex: 1,
    ),
    TimelineStopState.none => (
      fill: plate,
      content: cs.onSurface,
      // Thinner than the 3.6 it replaces: the number is the content, the ring
      // only has to lift it off the tiles.
      ring: cs.onSurface,
      ringWidth: 2,
      height: 32,
      text: _markerEta(i18n, eta),
      glyph: null,
      pill: false,
      zIndex: 0,
    ),
  };
}

/// Builds the stop layer. Reuses any marker whose rendered inputs are unchanged
/// via [cache], so a live frame costs O(changed) bitmap lookups rather than one
/// per stop on a route that can run 60 stops long.
///
/// [selectedUid] is the one stop showing its name as a capsule; [midLon] is the
/// route's mid-longitude, which decides the side that name leans towards.
Future<Set<Marker>> _buildStopMarkers({
  required List<BusStopModel> stops,
  required BusStopEtaViewModel? Function(BusStopModel) etaFor,
  required ColorScheme cs,
  required AppI18n i18n,
  required String? selectedUid,
  required double midLon,
  required Map<String, ({String key, Marker marker})> cache,
  required void Function(String stopUid) onTap,
}) async {
  final markers = <Marker>{};
  for (final st in stops) {
    if (st.lat == 0 && st.lon == 0) continue;
    final style = _markerStyle(i18n, etaFor(st), cs);
    final selected = st.stopUid == selectedUid;
    final key =
        '${cs.brightness}:${style.text}:${style.glyph?.codePoint}:'
        '${style.height}:${style.pill}:$selected:${st.lat},${st.lon}';
    final cached = cache[st.stopUid];
    if (cached != null && cached.key == key) {
      markers.add(cached.marker);
      continue;
    }
    final plate = await MapMarkers.stopMarker(
      fill: style.fill,
      content: style.content,
      ring: style.ring,
      ringWidth: style.ringWidth,
      height: style.height,
      text: style.text,
      glyph: style.glyph,
      pill: style.pill,
      label: selected ? st.stopName : null,
      labelFill: cs.onSurface,
      labelInk: cs.surface,
      // The name leans away from the route's middle, so it falls outside the
      // line rather than over it and the next stop along.
      flip: st.lon < midLon,
    );
    final stopUid = st.stopUid;
    final marker = Marker(
      markerId: MarkerId(stopUid),
      position: LatLng(st.lat, st.lon),
      icon: plate.icon,
      anchor: plate.anchor,
      // A selected capsule is wider than its plate and has to sit over its
      // neighbours; otherwise the ladder decides who wins an overlap.
      zIndexInt: selected ? 3 : style.zIndex,
      onTap: () => onTap(stopUid),
    );
    cache[stopUid] = (key: key, marker: marker);
    markers.add(marker);
  }
  return markers;
}

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

List<TimelineStop> _stopsFor(AppI18n i18n, BusRouteState s) {
  final cached = _stopsCache[s];
  if (cached != null) return cached;
  final stops = s.direction == 0 ? s.route?.stopsGo : s.route?.stopsReturn;
  final derived = stops == null
      ? const <TimelineStop>[]
      : deriveTimelineStops(
          i18n: i18n,
          stops: stops,
          etaMap: s.etaMap,
          direction: s.direction,
          bufferSequences: s.bufferSequences,
          pricingType: s.fare?.pricingType ?? 0,
        );
  _stopsCache[s] = derived;
  return derived;
}

// Strip is capped small for a horizontal glance, but the cap is a window
// around "now" rather than the first N trips of the day — otherwise a route
// opened at midday would show only its early-morning departures forever.
// The cap only applies while the window has a "now" to sit around; after the
// day's last departure the strip shows the full schedule instead.
const int _dtDepartureWindow = 12;

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
    if (time.isNotEmpty) rows.add(busClockLabel(time));
  }
  rows.sort();
  final nextIndex = rows.indexWhere((t) => busTimeIsUpcoming(t, now));
  if (nextIndex < 0) {
    // Service is over for the day: nothing to highlight (see _isUpcoming), so
    // the window has no anchor to sit around — show the whole day's schedule.
    return [for (final time in rows) (time: time, isNext: false)];
  }
  // Keep one past departure for context, then fill forward from "next".
  final start = nextIndex > 0 ? nextIndex - 1 : 0;
  final end = start + _dtDepartureWindow < rows.length
      ? start + _dtDepartureWindow
      : rows.length;
  return [
    for (final (i, time) in rows.sublist(start, end).indexed)
      (time: time, isNext: start + i == nextIndex),
  ];
}

/// Headsign for the current direction, shown once above the timetable board.
String _headsignFor(BusRouteState state) => state.currentHeadsign.isNotEmpty
    ? state.currentHeadsign
    : (state.currentStops.isEmpty ? '-' : state.currentStops.last.stopName);

/// Weekly service pattern for the direction on screen.
List<BusServiceEntry> _schedulesFor(BusRouteState state) => state.direction == 0
    ? (state.route?.schedulesGo ?? const [])
    : (state.route?.schedulesReturn ?? const []);

BusDayTimetable _timetableFor(BusRouteState state, int weekday) =>
    busTimetableForDay(
      weekday: weekday,
      schedules: _schedulesFor(state),
      todayTrips:
          state.daily?.tripsForDirection(state.direction) ??
          const <BusDailyTrip>[],
      isToday: weekday == busWeekdayIndex(DateTime.now()),
      now: TimeOfDay.now(),
    );

// Built per call rather than held in a const map: the names follow the
// rider's language.
List<String> _dtWeekdayLabels(AppI18n i18n) => [
  i18n.weekdayMon,
  i18n.weekdayTue,
  i18n.weekdayWed,
  i18n.weekdayThu,
  i18n.weekdayFri,
  i18n.weekdaySat,
  i18n.weekdaySun,
];

// TDX marks many 公路客運 routes 一段票 (flat fare) even when their decoded OD
// table carries genuine per-stop price variation. Showing that label next to
// a real 票價範圍 reads as self-contradictory, so a genuine range (min != max)
// wins over the raw enum instead of being labelled "flat".
String _farePricingTypeLabel(
  AppI18n i18n,
  int type, {
  bool hasFareRange = false,
}) {
  if (hasFareRange) return i18n.busFareByOd;
  return switch (type) {
    0 => i18n.busFareUnknownType,
    1 => i18n.busFareFlat,
    2 => i18n.busFareTwoSection,
    3 => i18n.busFareByDistance,
    _ => i18n.busFareOtherType(type),
  };
}

// TDX county code → display name, mirroring the mapping already used
// server-side (services/functions/vector.go) so a route's operating city
// doesn't leak an English identifier into the UI. Built per call rather than
// held in a const map: the names follow the rider's language.
//
// TDX spells several counties both with and without the `County` suffix, so
// both spellings are listed and resolve to the same name.
String _dtCityLabel(AppI18n i18n, String city) =>
    <String, String>{
      'Taipei': i18n.cityTaipei,
      'NewTaipei': i18n.cityNewTaipei,
      'Taoyuan': i18n.cityTaoyuan,
      'Taichung': i18n.cityTaichung,
      'Tainan': i18n.cityTainan,
      'Kaohsiung': i18n.cityKaohsiung,
      'Keelung': i18n.cityKeelung,
      'Hsinchu': i18n.cityHsinchuCity,
      'HsinchuCounty': i18n.cityHsinchuCounty,
      'MiaoliCounty': i18n.cityMiaoli,
      'ChanghuaCounty': i18n.cityChanghua,
      'NantouCounty': i18n.cityNantou,
      'YunlinCounty': i18n.cityYunlin,
      'ChiayiCounty': i18n.cityChiayiCounty,
      'Chiayi': i18n.cityChiayiCity,
      'PingtungCounty': i18n.cityPingtung,
      'YilanCounty': i18n.cityYilan,
      'HualienCounty': i18n.cityHualien,
      'TaitungCounty': i18n.cityTaitung,
      'PenghuCounty': i18n.cityPenghu,
      'KinmenCounty': i18n.cityKinmen,
      'LienchiangCounty': i18n.cityLienchiang,
      'InterCity': i18n.cityInterCity,
      'Miaoli': i18n.cityMiaoli,
      'Changhua': i18n.cityChanghua,
      'Nantou': i18n.cityNantou,
      'Yunlin': i18n.cityYunlin,
      'Pingtung': i18n.cityPingtung,
      'Yilan': i18n.cityYilan,
      'Hualien': i18n.cityHualien,
      'Taitung': i18n.cityTaitung,
      'Penghu': i18n.cityPenghu,
      'Kinmen': i18n.cityKinmen,
      'Lienchiang': i18n.cityLienchiang,
    }[city] ??
    city;
