import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/firebase/firebase_telemetry.dart';
import 'package:wheres_the_car/data/decoders/fare_decoder.dart';
import 'package:wheres_the_car/data/live/arrival_feed.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';
import 'package:wheres_the_car/data/reminders/reminder_toggle.dart';
import 'package:wheres_the_car/data/repositories/bus_repository.dart';
import 'package:wheres_the_car/data/repositories/firebase_repository.dart';
import 'package:wheres_the_car/data/repositories/reminders_repository.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_event.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_state.dart';

class BusRouteBloc extends Bloc<BusRouteEvent, BusRouteState> {
  BusRouteBloc({
    required this.subRouteUid,
    bool autoStart = true,
    BusRepository? busRepository,
    FirebaseRepository? firebaseRepository,
    RemindersRepository? remindersRepository,
  }) : _bus = busRepository ?? BusRepository.instance,
       _firebase = firebaseRepository ?? FirebaseRepository.instance,
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
  final BusRepository _bus;
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
      final route = await _bus.routeStatic(subRouteUid);
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
            source: () => _bus.routeEta(subRouteUid),
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
      daily = await _bus.routeDaily(subRouteUid);
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

  // The optimistic toggle choreography lives in the shared state machine; the
  // bus wiring adds the local mirror (RemindersRepository) and telemetry that
  // rail omits.
  late final ReminderToggle _reminderToggle = ReminderToggle(
    createReminder: ({
      required stopKey,
      required direction,
      required expiresAt,
    }) async {
      final reminder = await _firebase.createArrivalReminder(
        routeType: 'bus',
        routeKey: subRouteUid,
        stopKey: stopKey,
        direction: direction,
        leadMinutes: _leadMinutes,
        expiresAt: expiresAt,
      );
      return reminder.reminderId;
    },
    cancelReminder: _firebase.cancelArrivalReminder,
    persistArm: (stopKey, reminderId, expiresAt) =>
        _reminders.put(subRouteUid, stopKey, reminderId, expiresAt),
    persistDisarm: (stopKey) => _reminders.remove(subRouteUid, stopKey),
    onToggled: ({required enabled}) => unawaited(
      FirebaseTelemetry.instance.arrivalReminderChanged(
        routeType: 'bus',
        routeKey: subRouteUid,
        enabled: enabled,
        leadMinutes: _leadMinutes,
      ),
    ),
  );

  Future<void> _onReminderToggled(
    BusRouteReminderToggled event,
    Emitter<BusRouteState> emit,
  ) => _reminderToggle.run(
    readReminders: () => state.reminders,
    emit: (next) => emit(state.copyWith(reminders: next)),
    isDone: () => emit.isDone,
    key: event.stopUid,
    direction: '${state.direction}',
    armAt: DateTime.now().add(_reminderTtl),
  );

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
