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
  final String? error;

  MetroEtaState copyWith({
    List<MetroArrival>? arrivals,
    List<MetroSchedule>? schedule,
    bool? loading,
    String? error,
  }) => MetroEtaState(
    arrivals: arrivals ?? this.arrivals,
    schedule: schedule ?? this.schedule,
    loading: loading ?? this.loading,
    error: error,
  );

  @override
  List<Object?> get props => [arrivals, schedule, loading, error];
}
