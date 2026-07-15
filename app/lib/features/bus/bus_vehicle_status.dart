import 'package:wheres_the_car/data/models/bus_models.dart';

/// Severity lane for a vehicle's headline status, mapped to a theme color by
/// the view. Kept separate from the label so the palette stays in one place.
enum BusStatusTone { normal, notice, warning, muted }

typedef BusVehicleStatus = ({String label, BusStatusTone tone});

/// The single most rider-relevant state for the route-map bubble, folding TDX
/// 勤務狀態 (dutyStatus) and 行車狀況 (busStatus) into one headline. Ending duty
/// wins over the driving state — the bus is leaving service, which matters more
/// to a waiting rider than whatever it is doing right now.
BusVehicleStatus busVehicleStatus(BusVehiclePosition v) {
  if (v.dutyStatus == 2) return (label: '收班中', tone: BusStatusTone.muted);
  return switch (v.busStatus) {
    0 => (label: '營運中', tone: BusStatusTone.normal),
    1 => (label: '車禍', tone: BusStatusTone.warning),
    2 => (label: '故障', tone: BusStatusTone.warning),
    3 => (label: '塞車', tone: BusStatusTone.notice),
    4 => (label: '緊急', tone: BusStatusTone.warning),
    5 => (label: '加油', tone: BusStatusTone.muted),
    98 => (label: '偏移路線', tone: BusStatusTone.notice),
    99 => (label: '非營運', tone: BusStatusTone.muted),
    100 => (label: '客滿', tone: BusStatusTone.notice),
    101 => (label: '包車', tone: BusStatusTone.muted),
    // 90/91/255 不明/未知: the bus is reporting a position, so read it as
    // operating rather than surfacing an alarming "unknown" on every marker.
    _ => (label: '營運中', tone: BusStatusTone.normal),
  };
}

typedef BusGpsAge = ({String text, bool stale});

/// How fresh the vehicle's GPS fix is, for the bubble's second line.
/// [gpsUnix] is the fix time in epoch seconds (0 when TDX sent none). Beyond
/// 3 minutes the position is treated as stale — likely a bus whose GPS dropped.
BusGpsAge busGpsAge(int gpsUnix, DateTime now) {
  if (gpsUnix <= 0) return (text: '無定位', stale: true);
  final age = now.millisecondsSinceEpoch ~/ 1000 - gpsUnix;
  if (age >= 180) return (text: '定位延遲', stale: true);
  // Clock skew can put the fix slightly ahead of the device clock; read fresh.
  if (age < 15) return (text: '剛剛', stale: false);
  if (age < 60) return (text: '$age秒前', stale: false);
  return (text: '${age ~/ 60}分前', stale: false);
}
