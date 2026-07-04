import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/grpc/resilient_stream.dart';
import 'package:wheres_the_car/data/decoders/fare_decoder.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';
import 'package:wheres_the_car/data/repositories/bus_repository.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_event.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_state.dart';

class BusRouteBloc extends Bloc<BusRouteEvent, BusRouteState> {
  BusRouteBloc({required this.subRouteUid, bool autoStart = true})
    : super(const BusRouteState()) {
    on<BusRouteStarted>(_onStarted);
    on<BusRouteDirectionToggled>(_onDirectionToggled);
    on<BusRouteEtaUpdated>(_onEtaUpdated);
    on<BusRouteDetailsUpdated>(_onDetailsUpdated);
    on<BusRouteReminderToggled>(_onReminderToggled);
    on<BusRouteStreamFailed>(_onStreamFailed);
    on<BusRouteStreamRecovered>(_onStreamRecovered);
    if (autoStart) add(const BusRouteStarted());
  }

  final String subRouteUid;
  ResilientSubscription<List<BusStopEtaViewModel>>? _etaSub;

  static String etaKey(BusStopEtaViewModel eta) => eta.sequence > 0
      ? 'seq:${eta.direction}:${eta.sequence}'
      : 'uid:${eta.stopUid}';

  Future<void> _onStarted(
    BusRouteStarted _,
    Emitter<BusRouteState> emit,
  ) async {
    await _etaSub?.cancel();
    _etaSub = null;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final route = await BusRepository.instance.routeStatic(subRouteUid);
      emit(
        state.copyWith(
          route: route,
          fare: route.fare,
          bufferSequences: decodeBufferSequences(route.fare),
          loading: false,
        ),
      );

      _etaSub = ResilientSubscription<List<BusStopEtaViewModel>>(
        source: () => BusRepository.instance.routeEta(subRouteUid),
        onData: (etaList) {
          final map = {for (final e in etaList) etaKey(e): e};
          if (map.isEmpty) return;
          add(BusRouteEtaUpdated(map));
        },
        onFailure: (e) => add(BusRouteStreamFailed(e)),
        onRecovered: () => add(const BusRouteStreamRecovered()),
      );

      final details = await _loadDetails();
      if (details != null) {
        add(
          BusRouteDetailsUpdated(
            daily: details.daily,
            fare: details.fare,
          ),
        );
      }
    } on Object catch (e) {
      emit(state.copyWith(loading: false, error: AppError.from(e)));
    }
  }

  Future<({BusDailyTimetable? daily, BusFareInfo? fare})?>
  _loadDetails() async {
    BusDailyTimetable? daily;
    try {
      daily = await BusRepository.instance.routeDaily(subRouteUid);
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
      daily = null;
    }
    final fare = state.fare;
    if (daily == null && fare == null) return null;
    return (daily: daily, fare: fare);
  }

  void _onDirectionToggled(
    BusRouteDirectionToggled event,
    Emitter<BusRouteState> emit,
  ) {
    emit(state.copyWith(direction: event.direction));
  }

  void _onEtaUpdated(BusRouteEtaUpdated event, Emitter<BusRouteState> emit) {
    if (event.etaMap.isEmpty && state.etaMap.isNotEmpty) return;
    emit(state.copyWith(etaMap: event.etaMap));
  }

  void _onDetailsUpdated(
    BusRouteDetailsUpdated event,
    Emitter<BusRouteState> emit,
  ) {
    emit(
      state.copyWith(
        daily: event.daily,
        fare: event.fare,
        bufferSequences: decodeBufferSequences(event.fare),
      ),
    );
  }

  void _onReminderToggled(
    BusRouteReminderToggled event,
    Emitter<BusRouteState> emit,
  ) {
    final updated = Set<String>.from(state.reminders);
    if (updated.contains(event.stopUid)) {
      updated.remove(event.stopUid);
    } else {
      updated.add(event.stopUid);
    }
    emit(state.copyWith(reminders: updated));
  }

  void _onStreamFailed(
    BusRouteStreamFailed event,
    Emitter<BusRouteState> emit,
  ) {
    emit(state.copyWith(error: event.error));
  }

  void _onStreamRecovered(
    BusRouteStreamRecovered _,
    Emitter<BusRouteState> emit,
  ) {
    emit(state.copyWith(clearError: true));
  }

  @override
  Future<void> close() async {
    await _etaSub?.cancel();
    return super.close();
  }
}
