import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';

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
  final BusDailyTimetable? daily;
  final BusFareInfo? fare;
  final Set<int> bufferSequences;
  final int direction;

  /// Active arrival reminders on this route: stopUid -> server reminderId.
  ///
  // ponytail: reminders are one-shot and session-local — the backend marks
  // a reminder fired after sending the push but never tells the app, and
  // DeviceState has no reminders list, so this map cannot reflect
  // fired/expired state and resets when the screen closes. Fixing this
  // needs a listReminders RPC (proto change, wire-breaking, needs approval).
  final Map<String, String> reminders;
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
    BusDailyTimetable? daily,
    BusFareInfo? fare,
    Set<int>? bufferSequences,
    int? direction,
    Map<String, String>? reminders,
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
