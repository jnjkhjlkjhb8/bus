import 'package:equatable/equatable.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';

class MetroArrival extends Equatable {
  const MetroArrival({
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

  /// Seconds until arrival from the latest server frame, shown as-is (no local
  /// countdown) and re-synced when the next ~15s frame lands.
  final int estimateSeconds;

  /// Per-train identity threaded through for the 捷運下車提醒 bell + setup
  /// sheet (ADR-0015). All default empty for arrivals that carry no binding
  /// data (unpaired trains, non-TRTC systems).
  final String stationId;
  final String destinationStationId;
  final String system;
  final String trainNumber;
  final String cn1;

  /// Per-car congestion levels (1..3) in car order, only the reported cars.
  final List<int> congestion;

  /// Whether this arrival can host an alight-reminder bell: high-capacity TRTC
  /// trains only — the Wenhu line (BR) is excluded (ADR-0015).
  bool get supportsAlightReminder => system == 'TRTC' && line != 'BR';

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

/// One first/last-train row as the station sheet shows it: line code for
/// grouping, a readable destination, and both times on a 24-hour clock.
class MetroSchedule extends Equatable {
  const MetroSchedule({
    required this.line,
    required this.destination,
    required this.firstTime,
    required this.lastTime,
  });

  /// Line code (e.g. `R`). An interchange sheet carries rows from every line
  /// the station serves, so the list is grouped by this.
  final String line;

  /// Terminal station name (象山), or the raw TDX code when it falls outside
  /// the offline station list.
  final String destination;

  /// `HH:MM`, already normalised out of TDX's past-midnight form (`24:25` →
  /// `00:25`).
  final String firstTime;
  final String lastTime;

  @override
  List<Object?> get props => [line, destination, firstTime, lastTime];
}

class MetroEtaState extends Equatable {
  const MetroEtaState({
    this.arrivals = const [],
    this.schedule = const [],
    this.loading = false,
    this.error,
  });
  final List<MetroArrival> arrivals;
  final List<MetroSchedule> schedule;
  final bool loading;

  /// Live-stream health: set when the underlying ResilientSubscription gives
  /// up (the feed exhausted its reconnect attempts) and cleared only when it
  /// recovers. `arrivals` can go stale while this is set — the feed keeps
  /// showing the last-known list rather than blanking it, so this field is
  /// what lets the UI distinguish "current" from "silently stale" (F28).
  final AppError? error;

  MetroEtaState copyWith({
    List<MetroArrival>? arrivals,
    List<MetroSchedule>? schedule,
    bool? loading,
    AppError? error,
    bool clearError = false,
  }) => MetroEtaState(
    arrivals: arrivals ?? this.arrivals,
    schedule: schedule ?? this.schedule,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [arrivals, schedule, loading, error];
}
