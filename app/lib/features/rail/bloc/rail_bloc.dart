import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/core/storage/hive_store.dart';
import 'package:wheres_the_bus/data/live/arrival_feed.dart';
import 'package:wheres_the_bus/data/models/rail_fare_quote.dart';
import 'package:wheres_the_bus/data/repositories/thsr_repository.dart';
import 'package:wheres_the_bus/data/repositories/tra_repository.dart';
import 'package:wheres_the_bus/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_bus/features/rail/bloc/rail_state.dart';

class RailBloc extends Bloc<RailEvent, RailState> {
  RailBloc({
    TraRepository? traRepository,
    ThsrRepository? thsrRepository,
  }) : _traRepository = traRepository ?? TraRepository.instance,
       _thsrRepository = thsrRepository ?? ThsrRepository.instance,
       super(const RailInitial()) {
    on<RailSystemChanged>(_onSystemChanged);
    on<RailTimetableRequested>(_onTimetableRequested);
    on<RailTrainStopsRequested>(_onTrainStopsRequested);
    on<RailDelaysUpdated>(_onDelaysUpdated);
  }

  final TraRepository _traRepository;
  final ThsrRepository _thsrRepository;

  // Both handlers run concurrently (no transformer); a slow earlier request
  // can otherwise resolve after a newer one and clobber it.
  var _timetableGeneration = 0;
  var _trainStopsGeneration = 0;

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

  /// Sorts timetable results by the bound time — departure when [isDeparture],
  /// else arrival — and, when [cutoff] (minutes past midnight, the time the
  /// user picked) is set, keeps only trains departing at/after it (departure
  /// mode) or arriving at/before it (arrival mode). Unparseable times sort first
  /// and are never dropped, so bad data stays visible rather than vanishing.
  List<T> _sortedFiltered<T>(
    List<T> items,
    String Function(T) departureOf,
    String Function(T) arrivalOf,
    int? cutoff,
    bool isDeparture,
  ) {
    final keyOf = isDeparture ? departureOf : arrivalOf;
    final sorted = [...items]
      ..sort(
        (a, b) => (_minutesOfDay(keyOf(a)) ?? -1).compareTo(
          _minutesOfDay(keyOf(b)) ?? -1,
        ),
      );
    if (cutoff == null) return sorted;
    return sorted.where((item) {
      final m = _minutesOfDay(keyOf(item));
      if (m == null) return true;
      return isDeparture ? m >= cutoff : m <= cutoff;
    }).toList();
  }

  // A segment's delay map is a lone live value (a whole map per frame), not an
  // arrival list, so it stays on the feed's passthrough seam.
  StreamSubscription<Map<String, int>>? _delaySub;

  void _onSystemChanged(RailSystemChanged event, Emitter<RailState> emit) {
    // Reset to the pre-query prompt; results only exist after an explicit
    // timetable request for the newly selected system.
    emit(const RailInitial());
  }

  Future<void> _onTimetableRequested(
    RailTimetableRequested event,
    Emitter<RailState> emit,
  ) async {
    final gen = ++_timetableGeneration;
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

    // Remembered on request, not on success: the pair is what the rider asked
    // for, so a query that fails offline should still prefill next time.
    // Recorded here rather than in the query sheet so hand-offs that bypass
    // the sheet (station detail, home sheet) are covered by the same funnel.
    unawaited(
      HiveStore.addRecentOdQuery(
        system: system.name,
        originId: event.origin.id ?? '',
        originName: originName,
        destId: event.destination.id ?? '',
        destName: destName,
      ),
    );

    // A TRA delay subscription must not outlive its request: only the TRA
    // branch below starts a new one, so any request — TRA or THSR — first
    // cancels whatever the previous request left running. Without this, a
    // TRA request followed by a THSR request left the old TRA delay stream
    // subscribed, and a later TRA delay frame would apply onto the THSR
    // state through _onDelaysUpdated (F21).
    await _delaySub?.cancel();
    _delaySub = null;

    try {
      final originId = _stationId(event.origin);
      final destId = _stationId(event.destination);
      // Kept as a future so the fares and the timetable load concurrently.
      // TRA has no O/D-wide fare to fetch — see RailTimetableLoaded.fareQuote.
      final fareFuture = system == RailSystem.thsr
          ? _loadFares(event.date, originId, destId)
          : Future<RailFareQuote?>.value();
      if (system == RailSystem.tra) {
        final items = await _traRepository.timetable(
          event.date,
          originId,
          destId,
        );
        if (gen != _timetableGeneration) return;
        final fares = await fareFuture;
        emit(
          RailTimetableLoaded(
            system: system,
            originName: originName,
            destName: destName,
            date: event.date,
            fareQuote: fares,
            traItems: _sortedFiltered(
              items,
              (item) => item.departureTime,
              (item) => item.arrivalTime,
              event.cutoffMinutes,
              event.isDeparture,
            ),
          ),
        );
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
        if (gen != _timetableGeneration) return;
        final fares = await fareFuture;
        emit(
          RailTimetableLoaded(
            system: system,
            originName: originName,
            destName: destName,
            date: event.date,
            fareQuote: fares,
            thsrItems: _sortedFiltered(
              items,
              (item) => item.departureTime,
              (item) => item.arrivalTime,
              event.cutoffMinutes,
              event.isDeparture,
            ),
          ),
        );
      }
    } on Object catch (e) {
      if (gen != _timetableGeneration) return;
      emit(RailError(AppError.from(e)));
    }
  }

  /// Best-effort THSR fares for the O/D pair, every fare class and cabin class
  /// the pair prices. Station ids are already resolved here, so this is a
  /// direct RPC. Returns null on any failure (e.g. no landed fare, or non-prod
  /// without TDX data) so the timetable still renders without a price.
  ///
  /// The set is not narrowed to one price here: which fare a rider is quoted
  /// depends on their persisted ticket type, and the view resolves that so a
  /// preference change re-labels the screen without a refetch.
  Future<RailFareQuote?> _loadFares(
    String date,
    String originId,
    String destId,
  ) async {
    try {
      return RailFareQuote.thsr(
        fares: await _thsrRepository.fares(date, originId, destId),
      );
    } on Object {
      return null;
    }
  }

  /// The station id when the selection carries one, else its name. The router
  /// resolves rail station names to ids (臺/台-tolerant) on every rail RPC, so a
  /// bare name is a valid origin/destination — the app keeps no local station
  /// table to resolve against since offline search was removed.
  String _stationId(RailStationSelection selection) {
    final id = selection.id;
    return (id != null && id.isNotEmpty) ? id : selection.name;
  }

  @override
  Future<void> close() async {
    await _delaySub?.cancel();
    return super.close();
  }

  void _onDelaysUpdated(RailDelaysUpdated event, Emitter<RailState> emit) {
    final current = state;
    if (current is! RailTimetableLoaded) return;
    // Delays are TRA-only (THSR carries its own delayMinutes per item, no
    // separate stream). A frame from a delay subscription that outlived its
    // request — the cancel above is async and can't preempt a frame already
    // in flight — must not land on a THSR-loaded state (F21).
    if (current.system != RailSystem.tra) return;
    emit(current.copyWith(delays: event.delays));
  }

  Future<void> _onTrainStopsRequested(
    RailTrainStopsRequested event,
    Emitter<RailState> emit,
  ) async {
    final gen = ++_trainStopsGeneration;
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
        if (gen != _trainStopsGeneration) return;
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
        if (gen != _trainStopsGeneration) return;
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
      if (gen != _trainStopsGeneration) return;
      emit(RailError(AppError.from(e)));
    }
  }
}
