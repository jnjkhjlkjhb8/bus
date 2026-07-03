import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/generated/bus.pb.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';

class BusRouteState extends Equatable {
  const BusRouteState({
    this.route,
    this.etaMap = const {},
    this.daily,
    this.fare,
    this.bufferSequences = const {},
    this.direction = 0,
    this.reminders = const {},
    this.loading = true,
    this.error,
  });

  final BusRouteViewModel? route;
  final Map<String, BusStopEtaViewModel> etaMap;
  final Bus_DailyTimetables? daily;
  final Bus_Fare? fare;
  final Set<int> bufferSequences;
  final int direction;
  final Set<String> reminders;
  final bool loading;
  final AppError? error;

  List<BusStopModel> get currentStops =>
      direction == 0 ? (route?.stopsGo ?? []) : (route?.stopsReturn ?? []);

  String get currentHeadsign => direction == 0
      ? (route?.headsignGo ?? '')
      : (route?.headsignReturn ?? '');

  BusRouteState copyWith({
    BusRouteViewModel? route,
    Map<String, BusStopEtaViewModel>? etaMap,
    Bus_DailyTimetables? daily,
    Bus_Fare? fare,
    Set<int>? bufferSequences,
    int? direction,
    Set<String>? reminders,
    bool? loading,
    AppError? error,
    bool clearError = false,
  }) => BusRouteState(
    route: route ?? this.route,
    etaMap: etaMap ?? this.etaMap,
    daily: daily ?? this.daily,
    fare: fare ?? this.fare,
    bufferSequences: bufferSequences ?? this.bufferSequences,
    direction: direction ?? this.direction,
    reminders: reminders ?? this.reminders,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    route,
    etaMap,
    daily,
    fare,
    bufferSequences,
    direction,
    reminders,
    loading,
    error,
  ];
}
