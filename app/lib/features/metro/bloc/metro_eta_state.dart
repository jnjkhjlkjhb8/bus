import 'package:equatable/equatable.dart';

class MetroArrival extends Equatable {
  const MetroArrival({
    required this.line,
    required this.destination,
    required this.estimateMinutes,
    required this.approaching,
  });
  final String line;
  final String destination;
  final int estimateMinutes;
  final bool approaching;
  @override
  List<Object?> get props => [line, destination, estimateMinutes, approaching];
}

class MetroSchedule extends Equatable {
  const MetroSchedule({
    required this.destination,
    required this.firstTime,
    required this.lastTime,
  });
  final String destination;
  final String firstTime;
  final String lastTime;
  @override
  List<Object?> get props => [destination, firstTime, lastTime];
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
  final String? error;

  MetroEtaState copyWith({
    List<MetroArrival>? arrivals,
    List<MetroSchedule>? schedule,
    bool? loading,
    String? error,
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
