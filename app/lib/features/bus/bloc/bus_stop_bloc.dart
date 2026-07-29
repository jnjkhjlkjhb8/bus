import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/core/firebase/crash_reporter.dart';
import 'package:wheres_the_bus/data/live/arrival_feed.dart';
import 'package:wheres_the_bus/data/models/bus_models.dart';
import 'package:wheres_the_bus/data/repositories/bus_repository.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_stop_event.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_stop_state.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';

class BusStopBloc extends Bloc<BusStopEvent, BusStopState> {
  BusStopBloc({
    required AppI18n i18n,
    required this.stopId,
    this.city,
    BusRepository? repository,
  }) : _i18n = i18n,
       _repository = repository ?? BusRepository.instance,
       super(const BusStopState()) {
    on<BusStopStarted>(_onStarted);
    on<BusStopRetryRequested>(_onStarted);
    on<BusStopArrivalsUpdated>(_onUpdated);
    on<BusStopStationSelected>(_onStationSelected);
    on<BusStopFailed>(_onFailed);
    add(const BusStopStarted());
  }

  final String? stopId;
  final String? city;

  /// Captured at construction: a bloc has no `BuildContext` to resolve a
  /// locale from per frame. The arrival rows therefore keep the language the
  /// screen was opened in until it is rebuilt — acceptable because switching
  /// language re-runs the root `MaterialApp` builder, which tears this down.
  final AppI18n _i18n;
  final BusRepository _repository;
  // Replace policy + 15s decay live inside the feed; the empty-frame guard the
  // bloc used to run in _onUpdated is the feed's replace policy now.
  final _feed = ArrivalFeed<BusStopArrival>.replace(
    decay: (a, now) => a.decayed(now),
  );
  StreamSubscription<ArrivalFeedEmission<BusStopArrival>>? _sub;

  Future<void> _onStarted(BusStopEvent _, Emitter<BusStopState> emit) async {
    final id = stopId ?? '';
    if (id.isEmpty) {
      emit(state.copyWith(status: BusStopStatus.empty, clearError: true));
      return;
    }
    emit(state.copyWith(status: BusStopStatus.loading, clearError: true));
    await _sub?.cancel();
    try {
      final members = await _repository.stationGroup(id);
      if (members.isNotEmpty) {
        emit(state.copyWith(status: BusStopStatus.loaded, members: members));
      }
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
      // The station-group fetch is the only thing that can move the sheet out
      // of `loading` before the first ETA frame arrives. If it fails and the
      // ETA stream stays silent (no data, no terminal error — see
      // ResilientSubscription's clean-close backoff), nothing else ever
      // settles the state, so the sheet spins forever (F31). Settling here
      // immediately, rather than waiting on a timer, means a later ETA frame
      // can still recover the view the normal way (a source frame clears
      // `error` and flips status to loaded).
      emit(
        state.copyWith(status: BusStopStatus.error, error: AppError.from(e)),
      );
    }
    _sub = _feed
        .watch(
          source: () => _repository.stationEta(city ?? '', id),
          onFailure: (e) => add(BusStopFailed(e)),
        )
        .listen(
          (emission) => add(
            BusStopArrivalsUpdated(emission.arrivals, kind: emission.kind),
          ),
        );
  }

  void _onStationSelected(
    BusStopStationSelected event,
    Emitter<BusStopState> emit,
  ) {
    emit(
      event.stationUid == null
          ? state.copyWith(clearSelection: true)
          : state.copyWith(selectedStationUid: event.stationUid),
    );
  }

  void _onUpdated(BusStopArrivalsUpdated event, Emitter<BusStopState> emit) {
    final arrivalsChanged = !listEquals(event.arrivals, state.arrivals);
    final isSource = event.kind == ArrivalFeedEmissionKind.source;

    // A decay re-emission only re-derives already-known countdowns locally —
    // it learned nothing new from the network. It may refresh the displayed
    // values, but must never move `status` out of an error/loading state,
    // touch `updatedAt`, or clear `error`: only a real source frame proves
    // the feed is alive (F29, F30).
    if (!isSource) {
      if (!arrivalsChanged) return;
      final displays = [
        for (final a in event.arrivals) BusStopArrivalItem(_i18n, a),
      ]..sort((a, b) => a.rank.compareTo(b.rank));
      final byStation = <String, List<BusStopArrivalItem>>{};
      for (final item in displays) {
        byStation.putIfAbsent(item.stationId, () => []).add(item);
      }
      emit(
        state.copyWith(
          arrivals: event.arrivals,
          displays: displays,
          arrivalsByStation: byStation,
        ),
      );
      return;
    }

    // The feed applies the empty-frame guard and decay upstream; the bloc keeps
    // the status decision (empty only when no arrivals and no member stops).
    final status = event.arrivals.isEmpty && state.members.isEmpty
        ? BusStopStatus.empty
        : BusStopStatus.loaded;
    // An unchanged re-push (same values, new list instance) must leave the
    // derived view-model and freshness time untouched so the state stays equal
    // and the sheet does not rebuild. copyWith keeps the old values.
    if (!arrivalsChanged) {
      emit(state.copyWith(status: status, clearError: true));
      return;
    }
    // Arrivals moved: derive the sorted/grouped tile view-models here, off the
    // widget build path. The sheet build becomes pure layout over this.
    final displays = [
      for (final a in event.arrivals) BusStopArrivalItem(_i18n, a),
    ]..sort((a, b) => a.rank.compareTo(b.rank));
    final byStation = <String, List<BusStopArrivalItem>>{};
    for (final item in displays) {
      byStation.putIfAbsent(item.stationId, () => []).add(item);
    }
    emit(
      state.copyWith(
        status: status,
        arrivals: event.arrivals,
        displays: displays,
        arrivalsByStation: byStation,
        updatedAt: DateTime.now(),
        clearError: true,
      ),
    );
  }

  void _onFailed(BusStopFailed event, Emitter<BusStopState> emit) {
    emit(state.copyWith(status: BusStopStatus.error, error: event.error));
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
