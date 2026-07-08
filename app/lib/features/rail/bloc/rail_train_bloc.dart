import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/data/repositories/firebase_repository.dart';
import 'package:wheres_the_car/data/repositories/thsr_repository.dart';
import 'package:wheres_the_car/data/repositories/tra_repository.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_train_event.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_train_state.dart';

class RailTrainBloc extends Bloc<RailTrainEvent, RailTrainState> {
  RailTrainBloc({
    required this.type,
    required this.trainNo,
    required this.date,
    TraRepository? tra,
    ThsrRepository? thsr,
    FirebaseRepository? firebase,
  }) : _tra = tra ?? TraRepository.instance,
       _thsr = thsr ?? ThsrRepository.instance,
       _firebase = firebase ?? FirebaseRepository.instance,
       super(const RailTrainState()) {
    on<RailTrainStarted>(_onStarted);
    on<RailTrainReminderToggled>(_onReminderToggled);
  }

  final String type;
  final String trainNo;

  /// Service date in `yyyy-MM-dd`.
  final String date;

  final TraRepository _tra;
  final ThsrRepository _thsr;
  final FirebaseRepository _firebase;

  // ponytail: lead fixed at 3 min, matching the bus reminder. Read the
  // 'arrival_lead_minutes' remote-config and add a picker if per-user leads
  // are ever needed.
  static const _leadMinutes = 3;

  bool get _isThsr => type == '高鐵';
  String get _routeType => _isThsr ? 'thsr' : 'tra';

  Future<void> _onStarted(
    RailTrainStarted event,
    Emitter<RailTrainState> emit,
  ) async {
    emit(RailTrainState(reminders: state.reminders));
    try {
      final List<RailTrainStop> stops;
      if (_isThsr) {
        final raw = await _thsr.stops(date, trainNo);
        stops = raw
            .map(
              (s) => RailTrainStop(
                name: s.stationName,
                arrive: s.arrivalTime,
                depart: s.departureTime,
              ),
            )
            .toList();
      } else {
        final raw = await _tra.stops(date, trainNo);
        stops = raw
            .map(
              (s) => RailTrainStop(
                name: s.stationName,
                arrive: s.arrivalTime,
                depart: s.departureTime,
              ),
            )
            .toList();
      }

      if (stops.isEmpty) {
        emit(
          RailTrainState(
            status: RailTrainStatus.empty,
            reminders: state.reminders,
          ),
        );
        return;
      }

      emit(
        RailTrainState(
          status: RailTrainStatus.loaded,
          stops: stops,
          fullFare: await _loadFare(stops.first.name, stops.last.name),
          reminders: state.reminders,
        ),
      );
    } on Object catch (e) {
      // NotFound is a normal outcome (ADR-0005): a date beyond the landed
      // window or an unknown train renders the calm empty state, not an error.
      final error = AppError.from(e);
      emit(
        RailTrainState(
          status: error is NotFoundError
              ? RailTrainStatus.empty
              : RailTrainStatus.error,
          error: error,
          reminders: state.reminders,
        ),
      );
    }
  }

  /// Best-effort adult fare for the origin→destination pair. Returns null on
  /// any failure so the timetable still renders without a fare card.
  Future<int?> _loadFare(String originName, String destName) async {
    try {
      final table = _isThsr ? 'thsr_stations' : 'tra_stations';
      final originId = await _resolveStationId(table, originName);
      final destId = await _resolveStationId(table, destName);
      if (originId == null || destId == null) return null;

      if (_isThsr) {
        final fare = await _thsr.fare(date, originId, destId);
        return fare.price;
      }
      final fare = await _tra.fare('$originId:$destId', date);
      return fare.price;
    } on Object {
      return null;
    }
  }

  Future<String?> _resolveStationId(String table, String name) async {
    final rows = await PowerSyncService.instance.db.getAll(
      'SELECT station_id FROM $table WHERE station_name = ? LIMIT 1',
      [name],
    );
    if (rows.isEmpty) return null;
    return rows.first['station_id'] as String?;
  }

  Future<void> _onReminderToggled(
    RailTrainReminderToggled event,
    Emitter<RailTrainState> emit,
  ) async {
    final stopName = event.stopName;
    final existing = state.reminders[stopName];
    if (existing != null) {
      if (existing == 'pending') return;
      // Optimistic off; restore on failure.
      emit(
        state.copyWith(reminders: Map.of(state.reminders)..remove(stopName)),
      );
      try {
        if (!existing.startsWith('local:')) {
          await _firebase.cancelArrivalReminder(existing);
        }
      } on Object catch (e, s) {
        CrashReporter.record(e, s);
        if (emit.isDone) return;
        emit(
          state.copyWith(
            reminders: Map.of(state.reminders)..[stopName] = existing,
          ),
        );
      }
      return;
    }

    final arrivesAt = _arrivalDateTime(stopName);
    // No usable arrival time (unparseable / already departed) — nothing to arm.
    if (arrivesAt == null || !arrivesAt.isAfter(DateTime.now())) return;

    // Optimistic on with a placeholder; replace with the reminder id.
    emit(
      state.copyWith(
        reminders: Map.of(state.reminders)..[stopName] = 'pending',
      ),
    );
    try {
      final reminder = await _firebase.createArrivalReminder(
        routeType: _routeType,
        routeKey: trainNo,
        stopKey: stopName,
        direction: '0',
        leadMinutes: _leadMinutes,
        expiresAt: arrivesAt,
      );
      if (emit.isDone) return;
      emit(
        state.copyWith(
          reminders: Map.of(state.reminders)
            ..[stopName] = reminder.reminderId,
        ),
      );
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
      if (emit.isDone) return;
      emit(
        state.copyWith(reminders: Map.of(state.reminders)..remove(stopName)),
      );
    }
  }

  /// The stop's scheduled arrival (falling back to departure) as a local
  /// DateTime on the service [date], or null when it can't be parsed.
  DateTime? _arrivalDateTime(String stopName) {
    RailTrainStop? stop;
    for (final s in state.stops) {
      if (s.name == stopName) {
        stop = s;
        break;
      }
    }
    if (stop == null) return null;
    final time = stop.arrive.isNotEmpty ? stop.arrive : stop.depart;
    final d = date.split('-');
    final hm = time.split(':');
    if (d.length != 3 || hm.length < 2) return null;
    final year = int.tryParse(d[0]);
    final month = int.tryParse(d[1]);
    final day = int.tryParse(d[2]);
    final hour = int.tryParse(hm[0]);
    final minute = int.tryParse(hm[1]);
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null) {
      return null;
    }
    return DateTime(year, month, day, hour, minute);
  }
}
