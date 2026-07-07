import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
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
  }) : _tra = tra ?? TraRepository.instance,
       _thsr = thsr ?? ThsrRepository.instance,
       super(const RailTrainState()) {
    on<RailTrainStarted>(_onStarted);
  }

  final String type;
  final String trainNo;

  /// Service date in `yyyy-MM-dd`.
  final String date;

  final TraRepository _tra;
  final ThsrRepository _thsr;

  bool get _isThsr => type == '高鐵';

  Future<void> _onStarted(
    RailTrainStarted event,
    Emitter<RailTrainState> emit,
  ) async {
    emit(const RailTrainState());
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
        emit(const RailTrainState(status: RailTrainStatus.empty));
        return;
      }

      emit(
        RailTrainState(
          status: RailTrainStatus.loaded,
          stops: stops,
          fullFare: await _loadFare(stops.first.name, stops.last.name),
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
}
