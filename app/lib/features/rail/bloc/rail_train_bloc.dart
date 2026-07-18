import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/reminders/reminder_toggle.dart';
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

  // Lead fixed at 3 min, matching the bus reminder. Read the
  // 'arrival_lead_minutes' remote-config and add a picker if per-user leads
  // are ever needed.
  static const _leadMinutes = 3;

  bool get _isThsr => type == '高鐵';
  String get _routeType => _isThsr ? 'thsr' : 'tra';

  // Same optimistic toggle choreography as the bus route, minus the local
  // mirror and telemetry: rail arms against the stop's scheduled arrival and
  // keeps no persistent copy.
  late final ReminderToggle _reminderToggle = ReminderToggle(
    createReminder: ({
      required stopKey,
      required direction,
      required expiresAt,
    }) async {
      final reminder = await _firebase.createArrivalReminder(
        routeType: _routeType,
        routeKey: trainNo,
        stopKey: stopKey,
        direction: direction,
        leadMinutes: _leadMinutes,
        expiresAt: expiresAt,
      );
      return reminder.reminderId;
    },
    cancelReminder: _firebase.cancelArrivalReminder,
  );

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
      // The router resolves station names to ids, so the stop names go straight
      // to the fare RPC — the app no longer keeps a local station table.
      if (_isThsr) {
        final fare = await _thsr.fare(date, originName, destName);
        return fare.price;
      }
      final fare = await _tra.fare(originName, destName);
      return fare.price;
    } on Object {
      return null;
    }
  }

  Future<void> _onReminderToggled(
    RailTrainReminderToggled event,
    Emitter<RailTrainState> emit,
  ) => _reminderToggle.run(
    readReminders: () => state.reminders,
    emit: (next) => emit(state.copyWith(reminders: next)),
    isDone: () => emit.isDone,
    key: event.stopName,
    direction: '0',
    armAt: _arrivalDateTime(event.stopName),
  );

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
