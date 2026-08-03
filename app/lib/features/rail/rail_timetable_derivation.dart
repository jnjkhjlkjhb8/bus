/// Pure derivations behind the rail train screen's 時刻表 tab, split out of the
/// widget for the same reason `bus_timeline_stops.dart` is: the position
/// marker, the elapsed column and the dwell call-out are arithmetic over a
/// timetable, and arithmetic should be testable without pumping a widget tree.
library;

import 'package:flutter/widgets.dart';
import 'package:wheres_the_bus/features/rail/bloc/rail_train_state.dart';

/// Scales a fixed column width with the user's text size, so the slots still
/// fit their digits in the app's large-text mode instead of clipping the
/// figures they were sized around.
double scaledWidth(BuildContext context, double base) =>
    MediaQuery.textScalerOf(context).scale(base);

/// TRA spells its four 臺-prefixed stations (臺北/臺中/臺南/臺東) with 臺 in the
/// stop list, while search input and station pickers commonly carry the 台
/// variant. Comparing the two raw defeats every user-segment match at exactly
/// the busiest stations, so fold the variants before comparing names.
String normalizeStationName(String name) => name.trim().replaceAll('臺', '台');

bool sameStation(String a, String b) =>
    normalizeStationName(a) == normalizeStationName(b);

/// Trims the backend's `HH:mm:ss.ffffff` time strings down to `HH:mm`.
String hhmm(String t) => t.length >= 5 ? t.substring(0, 5) : t;

/// The stop's scheduled arrival (falling back to departure) as a local DateTime
/// on [serviceDate] (`yyyy-MM-dd`), or null when it can't be parsed.
DateTime? stopDateTime(String serviceDate, RailTrainStop stop) {
  final time = stop.arrive.isNotEmpty ? stop.arrive : stop.depart;
  final d = serviceDate.split('-');
  final hm = time.split(':');
  if (d.length != 3 || hm.length < 2) return null;
  final year = int.tryParse(d[0]);
  final month = int.tryParse(d[1]);
  final day = int.tryParse(d[2]);
  final hour = int.tryParse(hm[0]);
  final minute = int.tryParse(hm[1]);
  if (year == null ||
      month == null ||
      day == null ||
      hour == null ||
      minute == null) {
    return null;
  }
  return DateTime(year, month, day, hour, minute);
}

/// Where the train is along its own run, derived from the printed timetable
/// offset by the live delay.
///
/// There is no position feed for either operator — TRA publishes delay minutes
/// and nothing else, THSR publishes no realtime at all — so this is the honest
/// approximation: the last stop whose delayed scheduled time has already
/// passed. It is deliberately coarse; the marker it drives sits *between* rows
/// and never claims a point on the map.
///
/// Returns null when the run has not started, has already finished, or when a
/// time fails to parse. In all of those cases the screen shows no marker at
/// all, rather than pinning the train to an end of the line it isn't at.
int? railPositionIndex(
  List<RailTrainStop> stops,
  String serviceDate,
  int delayMinutes,
  DateTime now,
) {
  if (stops.isEmpty) return null;
  final delay = Duration(minutes: delayMinutes);
  var reached = 0;
  for (final stop in stops) {
    final scheduled = stopDateTime(serviceDate, stop);
    if (scheduled == null) return null;
    if (!scheduled.add(delay).isAfter(now)) reached++;
  }
  if (reached == 0 || reached >= stops.length) return null;
  return reached - 1;
}

/// Whole minutes from [from] to [to] along the run, or null when either time
/// can't be parsed or the pair is out of order.
int? elapsedMinutes(String serviceDate, RailTrainStop from, RailTrainStop to) {
  final start = stopDateTime(serviceDate, from);
  final end = stopDateTime(serviceDate, to);
  if (start == null || end == null) return null;
  final minutes = end.difference(start).inMinutes;
  return minutes < 0 ? null : minutes;
}

/// The train's dwell at a stop in whole minutes.
///
/// TRA prints a one-minute dwell at nearly every station, which is why the
/// screen only calls out two or more: a value every row shares is the default,
/// not information, and printing it 30 times was what pushed the old 抵達/開車
/// label pair onto every row of the list.
int dwellMinutes(RailTrainStop stop) {
  if (stop.arrive.isEmpty || stop.depart.isEmpty) return 0;
  final a = stop.arrive.split(':');
  final d = stop.depart.split(':');
  if (a.length < 2 || d.length < 2) return 0;
  final am = (int.tryParse(a[0]) ?? 0) * 60 + (int.tryParse(a[1]) ?? 0);
  final dm = (int.tryParse(d[0]) ?? 0) * 60 + (int.tryParse(d[1]) ?? 0);
  final diff = dm - am;
  return diff > 0 ? diff : 0;
}
