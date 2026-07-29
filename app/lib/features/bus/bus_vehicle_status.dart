import 'package:wheres_the_bus/data/models/bus_models.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';

/// Severity lane for a vehicle's headline status, mapped to a theme color by
/// the view. Kept separate from the label so the palette stays in one place.
enum BusStatusTone { normal, notice, warning, muted }

typedef BusVehicleStatus = ({String label, BusStatusTone tone});

/// The single most rider-relevant state for the route-map bubble, folding TDX
/// 勤務狀態 (dutyStatus) and 行車狀況 (busStatus) into one headline. Ending duty
/// wins over the driving state — the bus is leaving service, which matters more
/// to a waiting rider than whatever it is doing right now.
BusVehicleStatus busVehicleStatus(AppI18n i18n, BusVehiclePosition v) {
  if (v.dutyStatus == 2) {
    return (label: i18n.busStatusEndingDuty, tone: BusStatusTone.muted);
  }
  return switch (v.busStatus) {
    0 => (label: i18n.busStatusOperating, tone: BusStatusTone.normal),
    1 => (label: i18n.busStatusAccident, tone: BusStatusTone.warning),
    2 => (label: i18n.busStatusBreakdown, tone: BusStatusTone.warning),
    3 => (label: i18n.busStatusTraffic, tone: BusStatusTone.notice),
    4 => (label: i18n.busStatusEmergency, tone: BusStatusTone.warning),
    5 => (label: i18n.busStatusRefuelling, tone: BusStatusTone.muted),
    98 => (label: i18n.busStatusOffRoute, tone: BusStatusTone.notice),
    99 => (label: i18n.busStatusNotInService, tone: BusStatusTone.muted),
    100 => (label: i18n.busStatusFull, tone: BusStatusTone.notice),
    101 => (label: i18n.busStatusChartered, tone: BusStatusTone.muted),
    // 90/91/255 不明/未知: the bus is reporting a position, so read it as
    // operating rather than surfacing an alarming "unknown" on every marker.
    _ => (label: i18n.busStatusOperating, tone: BusStatusTone.normal),
  };
}

typedef BusGpsAge = ({String text, bool stale});

/// How fresh the vehicle's GPS fix is, for the bubble's second line.
/// [gpsUnix] is the fix time in epoch seconds (0 when TDX sent none). Beyond
/// 3 minutes the position is treated as stale — likely a bus whose GPS dropped.
BusGpsAge busGpsAge(AppI18n i18n, int gpsUnix, DateTime now) {
  if (gpsUnix <= 0) return (text: i18n.busGpsNone, stale: true);
  final age = now.millisecondsSinceEpoch ~/ 1000 - gpsUnix;
  if (age >= 180) return (text: i18n.busGpsStale, stale: true);
  // Clock skew can put the fix slightly ahead of the device clock; read fresh.
  if (age < 15) return (text: i18n.commonJustNow, stale: false);
  if (age < 60) return (text: i18n.busGpsSecondsAgo(age), stale: false);
  return (text: i18n.busGpsMinutesAgo(age ~/ 60), stale: false);
}
