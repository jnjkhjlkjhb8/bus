import 'package:equatable/equatable.dart';

/// One live metro arrival estimate. estimateSeconds is raw; callers apply
/// etaCeilMinutes (eta_format.dart) for display so the ceil rule has one owner.
///
/// Fields beyond the estimate carry the per-train identity the 捷運下車提醒
/// feature binds against (ADR-0015): [stationId] is the physical TDX station
/// the arrival is at, [trainNumber]/[cn1] identify the trip and its congestion
/// carriage pair, and [congestion] is the per-car crowding level (1..3, car
/// order, only cars the feed reported). They default empty because an arrival
/// that could not be paired ships without them — pairing never blocks the
/// countdown (congestion pairing, CONTEXT.md).
class MetroLiveArrival extends Equatable {
  const MetroLiveArrival({
    required this.line,
    required this.destination,
    required this.estimateSeconds,
    this.stationId = '',
    this.destinationStationId = '',
    this.system = '',
    this.trainNumber = '',
    this.cn1 = '',
    this.congestion = const [],
  });

  final String line;
  final String destination;
  final int estimateSeconds;

  /// Physical TDX station code the arrival is reported at (single-line code,
  /// e.g. `BL12`) — the board station a track session is created from.
  final String stationId;

  /// Terminal station code of the trip (e.g. `BL23`), used to derive the
  /// board→alight path client-side.
  final String destinationStationId;

  /// Metro operator code, e.g. `TRTC`. Reminders are TRTC-only (ADR-0015).
  final String system;

  /// Trip identifier (= congestion feed TrainNumber); empty when unpaired.
  final String trainNumber;

  /// Congestion carriage pair, e.g. `163/164`; empty when unpaired. The app
  /// derives the car id from its first half.
  final String cn1;

  /// Per-car congestion levels (1 light, 2 medium, 3 heavy) in car order,
  /// covering only the cars the feed reported (6 for high-capacity, 4 for
  /// Wenhu). Empty when the arrival has no congestion reading.
  final List<int> congestion;

  @override
  List<Object?> get props => [
    line,
    destination,
    estimateSeconds,
    stationId,
    destinationStationId,
    system,
    trainNumber,
    cn1,
    congestion,
  ];
}

/// One row of a station's first/last-train schedule, per line and destination.
class MetroScheduleEntry extends Equatable {
  const MetroScheduleEntry({
    required this.line,
    required this.destination,
    required this.firstTime,
    required this.lastTime,
  });

  factory MetroScheduleEntry.fromRow(Map<String, dynamic> row) =>
      MetroScheduleEntry(
        line: row['lineid'] as String,
        destination: row['destinationstaionid'] as String,
        firstTime: row['first_train_time'] as String,
        lastTime: row['last_train_time'] as String,
      );

  /// Line code the row belongs to (e.g. `R`). An interchange station sheet
  /// merges rows from every line it serves, so this is what groups them back.
  final String line;

  /// Terminal station code as TDX reports it (e.g. `R02`), not a name.
  final String destination;
  final String firstTime;
  final String lastTime;

  @override
  List<Object?> get props => [line, destination, firstTime, lastTime];
}
