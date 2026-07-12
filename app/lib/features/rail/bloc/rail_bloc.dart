import 'dart:async';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/live/arrival_feed.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';
import 'package:wheres_the_car/data/repositories/thsr_repository.dart';
import 'package:wheres_the_car/data/repositories/tra_repository.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_state.dart';

class RailBloc extends Bloc<RailEvent, RailState> {
  RailBloc({
    TraRepository? traRepository,
    ThsrRepository? thsrRepository,
    DateTime Function()? now,
  }) : _traRepository = traRepository ?? TraRepository.instance,
       _thsrRepository = thsrRepository ?? ThsrRepository.instance,
       _now = now ?? DateTime.now,
       super(const RailInitial()) {
    on<RailSystemChanged>(_onSystemChanged);
    on<RailStationSelected>(_onStationSelected);
    on<RailLiveBoardStarted>(_onLiveBoardStarted);
    on<RailLiveBoardStopped>(_onLiveBoardStopped);
    on<RailQueryChanged>(_onQueryChanged);
    on<RailTimetableRequested>(_onTimetableRequested);
    on<RailTrainStopsRequested>(_onTrainStopsRequested);
    on<RailDelaysUpdated>(_onDelaysUpdated);
    on<RailLiveBoardItemsUpdated>(_onLiveBoardItems);
    on<RailLiveBoardFailed>(_onLiveBoardFailed);
  }

  final TraRepository _traRepository;
  final ThsrRepository _thsrRepository;

  /// Clock seam so tests can pin "today" when filtering departed trains.
  final DateTime Function() _now;

  static final _dateFormat = DateFormat('yyyy-MM-dd');

  /// Minutes past midnight for a backend time string (RFC3339 timestamp or a
  /// bare `HH:mm:ss` clock), or null when unparseable.
  static int? _minutesOfDay(String t) {
    final s = t.contains('T') ? t.split('T').last : t;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  /// Sorts timetable results by departure time and, when [date] is today,
  /// drops trains that have already departed. Unparseable times sort first
  /// and are never dropped, so bad data stays visible rather than vanishing.
  List<T> _upcomingSorted<T>(
    List<T> items,
    String Function(T) departureOf,
    String date,
  ) {
    final sorted = [...items]
      ..sort(
        (a, b) => (_minutesOfDay(departureOf(a)) ?? -1).compareTo(
          _minutesOfDay(departureOf(b)) ?? -1,
        ),
      );
    final now = _now();
    if (date != _dateFormat.format(now)) return sorted;
    final cutoff = now.hour * 60 + now.minute;
    return sorted.where((item) {
      final m = _minutesOfDay(departureOf(item));
      return m == null || m >= cutoff;
    }).toList();
  }

  // The live departure board is an arrival list: it rides the arrival feed's
  // replace policy (empty-frame guard + departure sort), the same policy the
  // home-sheet TraStationBloc uses on this stream, so the two can't drift.
  final _liveBoardFeed = ArrivalFeed<TraLiveBoardItem>.replace(
    compare: TraLiveBoardItem.byDeparture,
  );
  StreamSubscription<List<TraLiveBoardItem>>? _liveBoardSub;

  // A segment's delay map is a lone live value (a whole map per frame), not an
  // arrival list, so it stays on the feed's passthrough seam.
  StreamSubscription<Map<String, int>>? _delaySub;

  RailLiveBoardLoaded _defaultLoaded(RailSystem system) {
    final now = DateTime.now();
    return RailLiveBoardLoaded(
      system: system,
      stationId: '',
      stationName: '桃園',
      traItems: const [],
      queryOriginId: '',
      queryOriginName: '起點站',
      queryDestId: '',
      queryDestName: '終點站',
      queryDate: now,
      queryTime: TimeOfDay.fromDateTime(now),
      departureMode: true,
    );
  }

  void _onSystemChanged(RailSystemChanged event, Emitter<RailState> emit) {
    final current = state;
    if (current is RailLiveBoardLoaded) {
      emit(current.copyWith(system: event.system));
    } else {
      emit(_defaultLoaded(event.system));
    }
  }

  void _onStationSelected(RailStationSelected event, Emitter<RailState> emit) {
    final current = state;
    if (current is RailLiveBoardLoaded) {
      emit(
        current.copyWith(
          stationId: event.stationId,
          stationName: event.stationName,
        ),
      );
    } else {
      emit(
        _defaultLoaded(RailSystem.tra).copyWith(
          stationId: event.stationId,
          stationName: event.stationName,
        ),
      );
    }
    add(const RailLiveBoardStarted());
  }

  Future<void> _onLiveBoardStarted(
    RailLiveBoardStarted event,
    Emitter<RailState> emit,
  ) async {
    final current = state;
    final system = current is RailLiveBoardLoaded
        ? current.system
        : RailSystem.tra;
    final stationId = current is RailLiveBoardLoaded ? current.stationId : '';
    if (stationId.isEmpty || system != RailSystem.tra) return;
    if (current is! RailLiveBoardLoaded) {
      emit(_defaultLoaded(system).copyWith(stationId: stationId));
    }

    final date = _dateFormat.format(DateTime.now());
    await _liveBoardSub?.cancel();
    _liveBoardSub = _liveBoardFeed
        .watch(
          source: () => _traRepository.liveBoard(stationId, date),
          onFailure: (e) => add(RailLiveBoardFailed(e)),
        )
        .listen((items) => add(RailLiveBoardItemsUpdated(items)));
  }

  void _onLiveBoardItems(
    RailLiveBoardItemsUpdated event,
    Emitter<RailState> emit,
  ) {
    final current = state;
    if (current is RailLiveBoardLoaded) {
      emit(current.copyWith(traItems: event.items));
    }
  }

  void _onLiveBoardFailed(
    RailLiveBoardFailed event,
    Emitter<RailState> emit,
  ) {
    emit(RailError(event.error));
  }

  Future<void> _onLiveBoardStopped(
    RailLiveBoardStopped event,
    Emitter<RailState> emit,
  ) async {
    await _liveBoardSub?.cancel();
  }

  void _onQueryChanged(RailQueryChanged event, Emitter<RailState> emit) {
    final current = state;
    if (current is RailLiveBoardLoaded) {
      emit(
        current.copyWith(
          queryOriginId: event.originId,
          queryOriginName: event.originName,
          queryDestId: event.destId,
          queryDestName: event.destName,
          queryDate: event.date,
          queryTime: event.time,
          departureMode: event.departureMode,
        ),
      );
    }
  }

  Future<void> _onTimetableRequested(
    RailTimetableRequested event,
    Emitter<RailState> emit,
  ) async {
    final system = event.system;
    final originName = event.origin.name;
    final destName = event.destination.name;

    emit(
      RailTimetableLoading(
        system: system,
        originName: originName,
        destName: destName,
        date: event.date,
      ),
    );

    try {
      final originId = await _stationId(system, event.origin);
      final destId = await _stationId(system, event.destination);
      if (system == RailSystem.tra) {
        final items = await _traRepository.timetable(
          event.date,
          originId,
          destId,
        );
        emit(
          RailTimetableLoaded(
            system: system,
            originName: originName,
            destName: destName,
            date: event.date,
            traItems: _upcomingSorted(
              items,
              (item) => item.departureTime,
              event.date,
            ),
          ),
        );
        await _delaySub?.cancel();
        _delaySub = ArrivalFeed.passthrough(
          source: () => _traRepository.delay(
            event.date,
            originId,
            destId,
          ),
        ).listen((delays) => add(RailDelaysUpdated(delays)));
      } else {
        final items = await _thsrRepository.timetable(
          event.date,
          originId,
          destId,
        );
        emit(
          RailTimetableLoaded(
            system: system,
            originName: originName,
            destName: destName,
            date: event.date,
            thsrItems: _upcomingSorted(
              items,
              (item) => item.departureTime,
              event.date,
            ),
          ),
        );
      }
    } on Object catch (e) {
      emit(RailError(AppError.from(e)));
    }
  }

  Future<String> _stationId(
    RailSystem system,
    RailStationSelection selection,
  ) async {
    final knownId = selection.id;
    if (knownId != null && knownId.isNotEmpty) return knownId;
    final resolved = system == RailSystem.tra
        ? await _traRepository.stationId(selection.name)
        : await _thsrRepository.stationId(selection.name);
    return resolved ?? selection.name;
  }

  @override
  Future<void> close() async {
    await _liveBoardSub?.cancel();
    await _delaySub?.cancel();
    return super.close();
  }

  void _onDelaysUpdated(RailDelaysUpdated event, Emitter<RailState> emit) {
    final current = state;
    if (current is! RailTimetableLoaded) return;
    emit(current.copyWith(delays: event.delays));
  }

  Future<void> _onTrainStopsRequested(
    RailTrainStopsRequested event,
    Emitter<RailState> emit,
  ) async {
    try {
      final current = state;
      final system = current is RailTimetableLoaded
          ? current.system
          : RailSystem.tra;
      if (system == RailSystem.tra) {
        final stops = await _traRepository.stops(
          event.date,
          event.trainNo,
        );
        emit(
          RailTrainStopsLoaded(
            system: system,
            trainNo: event.trainNo,
            trainType: '台鐵',
            traStops: stops,
          ),
        );
      } else {
        final stops = await _thsrRepository.stops(
          event.date,
          event.trainNo,
        );
        emit(
          RailTrainStopsLoaded(
            system: system,
            trainNo: event.trainNo,
            trainType: '高鐵',
            thsrStops: stops,
          ),
        );
      }
    } on Object catch (e) {
      emit(RailError(AppError.from(e)));
    }
  }
}
