import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_bus/data/live/arrival_feed.dart';
import 'package:wheres_the_bus/data/models/bike_models.dart';
import 'package:wheres_the_bus/data/repositories/bike_repository.dart';
import 'package:wheres_the_bus/features/bike/bloc/bike_station_event.dart';
import 'package:wheres_the_bus/features/bike/bloc/bike_station_state.dart';

class BikeStationBloc extends Bloc<BikeStationEvent, BikeStationState> {
  /// [name], [lat] and [lon] seed the initial state with what the caller
  /// already knows (search results carry all three), so the title and camera
  /// are right on the first frame. The static fetch still runs and overwrites
  /// them with the authoritative values.
  BikeStationBloc({
    required this.stationUid,
    BikeRepository? repository,
    String? name,
    double? lat,
    double? lon,
  }) : _repository = repository ?? BikeRepository.instance,
       super(
         BikeStationState(
           name: name ?? '',
           lat: lat ?? 0,
           lon: lon ?? 0,
         ),
       ) {
    on<BikeStationStarted>(_onStarted);
    on<BikeStationEtaUpdated>(_onEta);
    on<BikeStationEtaFailed>(_onEtaFailed);
    on<BikeStationEtaRecovered>(_onEtaRecovered);
    add(const BikeStationStarted());
  }

  final String stationUid;
  final BikeRepository _repository;

  // Availability is a lone live value, not an arrival list, so it rides the
  // arrival feed's passthrough seam: resilient reconnect/backoff without any
  // merge/decay/sort. It gains no arrival semantics from sharing the seam.
  StreamSubscription<BikeAvailability>? _sub;

  Future<void> _onStarted(
    BikeStationStarted _,
    Emitter<BikeStationState> emit,
  ) async {
    try {
      final info = await _repository.stationStatic(stationUid);
      emit(
        state.copyWith(
          name: info.name,
          capacity: info.capacity,
          // A station whose point never landed comes back as 0/0. That is
          // "unknown", not a location off West Africa, so it must not clobber
          // coordinates the caller already handed in — passing null here keeps
          // the seeded pair through `copyWith`.
          lat: info.lat != 0 ? info.lat : null,
          lon: info.lon != 0 ? info.lon : null,
          loading: false,
          clearError: true,
        ),
      );
    } on Object catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
    // Subscribed regardless of the static fetch outcome: the live counts are
    // independent of the station's name/capacity, and a static failure must
    // not also silently drop the live feed. Only await a cancel when there is
    // a prior subscription to replace — an unconditional `await` here would
    // introduce a yield point between the loading:false emission above and
    // this assignment, letting a close() that races right behind the state
    // update land before `_sub` exists.
    if (_sub != null) await _sub!.cancel();
    _sub =
        ArrivalFeed.passthrough(
          source: () => _repository.stationEta(stationUid),
          // Wired through to state.liveError, kept separate from the static
          // `error` above: a station-info success can't paper over a live
          // stream that never came up, so `available == 0` while `liveError`
          // is set reads as stale, not a confirmed empty station (F27).
          onFailure: (e) => add(BikeStationEtaFailed(e)),
          onRecovered: () => add(const BikeStationEtaRecovered()),
        ).listen(
          (a) => add(
            BikeStationEtaUpdated(
              available: a.available,
              returnDocks: a.returnDocks,
              generalBikes: a.generalBikes,
              electricBikes: a.electricBikes,
            ),
          ),
        );
  }

  void _onEta(BikeStationEtaUpdated e, Emitter<BikeStationState> emit) {
    emit(
      state.copyWith(
        available: e.available,
        returnDocks: e.returnDocks,
        generalBikes: e.generalBikes,
        electricBikes: e.electricBikes,
        hasLiveData: true,
        updatedAt: DateTime.now(),
        clearLiveError: true,
      ),
    );
  }

  void _onEtaFailed(BikeStationEtaFailed e, Emitter<BikeStationState> emit) {
    emit(state.copyWith(liveError: e.error));
  }

  void _onEtaRecovered(
    BikeStationEtaRecovered e,
    Emitter<BikeStationState> emit,
  ) {
    emit(state.copyWith(clearLiveError: true));
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
