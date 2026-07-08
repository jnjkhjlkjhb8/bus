import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/firebase/firebase_telemetry.dart';
import 'package:wheres_the_car/data/decoders/fare_decoder.dart';
import 'package:wheres_the_car/data/live/arrival_feed.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';
import 'package:wheres_the_car/data/repositories/bus_repository.dart';
import 'package:wheres_the_car/data/repositories/firebase_repository.dart';
import 'package:wheres_the_car/data/repositories/reminders_repository.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_event.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_state.dart';

class BusRouteBloc extends Bloc<BusRouteEvent, BusRouteState> {
  BusRouteBloc({
    required this.subRouteUid,
    bool autoStart = true,
    FirebaseRepository? firebaseRepository,
    RemindersRepository? remindersRepository,
  }) : _firebase = firebaseRepository ?? FirebaseRepository.instance,
       _reminders = remindersRepository ?? RemindersRepository.instance,
       super(const BusRouteState()) {
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
  final FirebaseRepository _firebase;
  final RemindersRepository _reminders;
  // Replace policy + 15s decay live inside the feed; the bloc keys the emitted
  // list into etaMap on arrival (etaKey), preserving the map-shaped state.
  final _feed = ArrivalFeed<BusStopEtaViewModel>.replace(
    decay: (e, now) => e.decayed(now),
  );
  StreamSubscription<List<BusStopEtaViewModel>>? _etaSub;

  static String etaKey(BusStopEtaViewModel eta) => eta.sequence > 0
      ? 'seq:${eta.direction}:${eta.sequence}'
      : 'uid:${eta.stopUid}';

  Future<void> _onStarted(
    BusRouteStarted _,
    Emitter<BusRouteState> emit,
  ) async {
    await _etaSub?.cancel();
    _etaSub = null;
    emit(
      state.copyWith(
        loading: true,
        clearError: true,
        reminders: _reminders.active(subRouteUid),
      ),
    );
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

      _etaSub = _feed
          .watch(
            source: () => BusRepository.instance.routeEta(subRouteUid),
            onFailure: (e) => add(BusRouteStreamFailed(e)),
            onRecovered: () => add(const BusRouteStreamRecovered()),
          )
          .listen(
            (etaList) => add(
              BusRouteEtaUpdated({
                for (final e in etaList) etaKey(e): e,
              }),
            ),
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
    // The feed guards empty frames upstream; this stays a defensive no-op.
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

  // Fixed lead until a per-user picker exists; remote-config
  // 'arrival_lead_minutes' offers '1,3,5'.
  static const _leadMinutes = 3;
  static const _reminderTtl = Duration(hours: 2);

  Future<void> _onReminderToggled(
    BusRouteReminderToggled event,
    Emitter<BusRouteState> emit,
  ) async {
    final existing = state.reminders[event.stopUid];
    if (existing != null) {
      if (existing == 'pending') return;
      // Optimistic off; restore on failure.
      emit(
        state.copyWith(
          reminders: Map.of(state.reminders)..remove(event.stopUid),
        ),
      );
      try {
        if (!existing.startsWith('local:')) {
          await _firebase.cancelArrivalReminder(existing);
        }
        await _reminders.remove(subRouteUid, event.stopUid);
        unawaited(
          FirebaseTelemetry.instance.arrivalReminderChanged(
            routeType: 'bus',
            routeKey: subRouteUid,
            enabled: false,
            leadMinutes: _leadMinutes,
          ),
        );
      } on Object catch (e, s) {
        CrashReporter.record(e, s);
        if (emit.isDone) return;
        emit(
          state.copyWith(
            reminders: Map.of(state.reminders)..[event.stopUid] = existing,
          ),
        );
      }
      return;
    }
    // Optimistic on with a placeholder id; replace with the server id.
    emit(
      state.copyWith(
        reminders: Map.of(state.reminders)..[event.stopUid] = 'pending',
      ),
    );
    try {
      final expiresAt = DateTime.now().add(_reminderTtl);
      final reminder = await _firebase.createArrivalReminder(
        routeType: 'bus',
        routeKey: subRouteUid,
        stopKey: event.stopUid,
        direction: '${state.direction}',
        leadMinutes: _leadMinutes,
        expiresAt: expiresAt,
      );
      if (emit.isDone) return;
      emit(
        state.copyWith(
          reminders: Map.of(state.reminders)
            ..[event.stopUid] = reminder.reminderId,
        ),
      );
      await _reminders.put(
        subRouteUid,
        event.stopUid,
        reminder.reminderId,
        expiresAt,
      );
      unawaited(
        FirebaseTelemetry.instance.arrivalReminderChanged(
          routeType: 'bus',
          routeKey: subRouteUid,
          enabled: true,
          leadMinutes: _leadMinutes,
        ),
      );
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
      if (emit.isDone) return;
      emit(
        state.copyWith(
          reminders: Map.of(state.reminders)..remove(event.stopUid),
        ),
      );
    }
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
