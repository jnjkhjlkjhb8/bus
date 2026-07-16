/// Shared ETA formatting for every transit mode. Two rules the app must never
/// diverge on live here: seconds always ceil to minutes, and one status-code
/// mapping owns the arrival/departure/service-state labels.
library;

/// Approved domain rule: display always rounds seconds UP to minutes (ceil),
/// never round or floor. Non-positive seconds mean "no estimate" -> 0.
int etaCeilMinutes(int seconds) => seconds > 0 ? (seconds / 60).ceil() : 0;

/// The one arrival-instant decay derivation, shared by decode (fresh frame) and
/// local decay (between frames). Given the canonical [arrivalUnix] (absolute
/// wall-clock arrival, Unix seconds) it derives remaining seconds against [now]
/// so the countdown stays accurate without a new server frame; a just-passed
/// instant clamps to 0. When [arrivalUnix] is non-positive (server sent no
/// absolute instant) the server-provided [serverEstimateSeconds] is used as-is.
int etaRemainingSeconds({
  required int arrivalUnix,
  required int serverEstimateSeconds,
  required DateTime now,
}) {
  if (arrivalUnix <= 0) return serverEstimateSeconds;
  final seconds = arrivalUnix - now.millisecondsSinceEpoch ~/ 1000;
  return seconds > 0 ? seconds : 0;
}

/// Exhaustive interpretation of a bus stop's estimate + TDX stop-status code.
enum BusStopDisplayStatus {
  arriving,
  departingSoon,
  minutes,
  notDeparted,
  trafficControl,
  lastBusPassed,
  notOperating,
  unknown,
}

/// The one status-code mapping. stopStatus codes are TDX StopStatus values:
/// 0 = normal, 1 = not yet departed, 2 = traffic control, 3 = last bus passed,
/// 4 = not operating today.
BusStopDisplayStatus busStopDisplayStatus({
  required int estimateSeconds,
  required int stopStatus,
}) {
  // A positive estimate always reads as a countdown, whatever the status code:
  // the backend fills status-1 gaps with a predicted NextBusTime and derives
  // arrivalUnix from it precisely so the app can count down (bus_eta.go). Only
  // a live bus (status 0) may read as arriving when the countdown hits zero;
  // a predicted status-1 estimate that decays to zero falls back to its
  // status label instead.
  if (stopStatus == 0 && estimateSeconds == 0) {
    return BusStopDisplayStatus.arriving;
  }
  if (estimateSeconds > 0 && estimateSeconds < 60) {
    return BusStopDisplayStatus.departingSoon;
  }
  if (estimateSeconds > 0) return BusStopDisplayStatus.minutes;
  return switch (stopStatus) {
    1 => BusStopDisplayStatus.notDeparted,
    2 => BusStopDisplayStatus.trafficControl,
    3 => BusStopDisplayStatus.lastBusPassed,
    4 => BusStopDisplayStatus.notOperating,
    _ => BusStopDisplayStatus.unknown,
  };
}

/// The one display-label function. Returns the user-facing string ('2分',
/// '進站中', a clock time, or a service-state label), or null when nothing is
/// known.
String? busStopDisplayLabel({
  required int estimateSeconds,
  required int stopStatus,
  required String nextBusTime,
}) {
  // A not-yet-departed stop (status 1) is a scheduled departure: show its
  // NextBusTime clock (HH:mm) rather than the countdown derived from it.
  if (stopStatus == 1) {
    final clock = _clockLabel(nextBusTime);
    if (clock != null) return clock;
  }
  // Any positive live estimate shows the countdown; 進站中 is reserved for a
  // live bus at zero.
  if (estimateSeconds > 0) return '${etaCeilMinutes(estimateSeconds)}分';
  if (stopStatus == 0) return '進站中';
  return _clockLabel(nextBusTime) ??
      switch (stopStatus) {
        1 => '尚未發車',
        2 => '交管不停靠',
        3 => '末班已過',
        4 => '今日未營運',
        _ => null,
      };
}

String? _clockLabel(String value) {
  if (value.isEmpty) return null;
  final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(value);
  if (match != null) {
    final h = match.group(1)!.padLeft(2, '0');
    return '$h:${match.group(2)!}';
  }
  final parsed = DateTime.tryParse(value);
  if (parsed != null) return _hhmm(parsed.toLocal());
  return null;
}

String _hhmm(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  return '$h:${t.minute.toString().padLeft(2, '0')}';
}
