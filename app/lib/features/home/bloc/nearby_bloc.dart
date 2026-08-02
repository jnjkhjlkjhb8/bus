import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/core/location/location_service.dart';
import 'package:wheres_the_bus/data/repositories/near_repository.dart';
import 'package:wheres_the_bus/features/home/bloc/nearby_event.dart';
import 'package:wheres_the_bus/features/home/bloc/nearby_state.dart';

/// Drives the home map's nearby-station queries over a single long-lived
/// bidirectional stream rather than one stream per query.
///
/// The router answers that stream latest-wins: a viewport superseded before it
/// was picked up is dropped server-side, so responses are ordered but not
/// one-per-request. That makes "the newest response is the current answer" true
/// by construction — there is no stale result to guard against on arrival, only
/// a stale *enqueue* when a GPS fix resolves after a newer query was issued.
class NearbyBloc extends Bloc<NearbyEvent, NearbyState> {
  NearbyBloc({NearRepository? repository, NearCache? cache})
    : _repository = repository ?? NearRepository.instance,
      _cache = cache ?? NearCache.instance,
      super(const NearbyState()) {
    on<NearbyRequested>(_onRequested);
    on<NearbyRetried>(_onRetried);
    on<NearbyStationsReceived>(_onStationsReceived);
    on<NearbyStreamFailed>(_onStreamFailed);
  }

  final NearRepository _repository;
  final NearCache _cache;

  /// Coordinates the in-flight query actually went out with — the event's own
  /// may be null (GPS-resolved), and the response stream is latest-wins, so
  /// this is what the arriving answer is about.
  ({double lat, double lon})? _lastOrigin;

  /// The most recently issued query, kept even on failure so [NearbyRetried]
  /// replays the same dragged viewport instead of falling back to GPS.
  NearbyRequested? _lastAttempted;

  /// Issue counter, compared after the GPS await so a query whose fix resolved
  /// late doesn't enqueue behind the newer one that overtook it.
  var _issued = 0;

  /// Whether the query in flight is already a replay of one a dropped stream
  /// swallowed — see [_onStreamFailed]. Bounds the recovery to a single extra
  /// attempt, so a backend that is genuinely down still reaches the rider.
  var _replayed = false;

  StreamController<NearQuery>? _queries;

  // Cancelled in _detachStream, which both close() and the failure handler go
  // through; the lint only recognises a cancel in the creating function.
  // ignore: cancel_subscriptions
  StreamSubscription<List<NearStationViewModel>>? _responses;

  Future<void> _onRetried(
    NearbyRetried event,
    Emitter<NearbyState> emit,
  ) async {
    final last = _lastAttempted;
    if (last == null) return;
    await _send(last, emit);
  }

  Future<void> _onRequested(
    NearbyRequested event,
    Emitter<NearbyState> emit,
  ) async {
    _lastAttempted = event;
    _replayed = false;
    await _send(event, emit);
  }

  void _onStationsReceived(
    NearbyStationsReceived event,
    Emitter<NearbyState> emit,
  ) {
    _replayed = false;
    final stations = [...event.stations]
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    emit(state.copyWith(stations: stations, loading: false, clearError: true));
    final origin = _lastOrigin;
    if (origin != null) {
      unawaited(_cache.save(origin.lat, origin.lon, stations));
    }
  }

  void _onStreamFailed(NearbyStreamFailed event, Emitter<NearbyState> emit) {
    // A broken gRPC stream stays broken, so drop it here and let the next
    // query open a fresh one.
    _detachStream();
    // Nothing was waiting on it. The stream sits open across the whole session,
    // so it is mostly idle — long enough, while the rider is on another page,
    // for the connection under it to be dropped (the channel's own idle
    // timeout, a NAT, a server restart). That drop answers no query, so it must
    // not replace the stations already on screen with an error the rider then
    // has to dismiss by hand; the next viewport query reopens the stream.
    if (!state.loading) return;
    // A query *was* in flight, and its answer is now never coming. Replay it
    // once on a fresh stream — only a second failure is the backend saying no.
    final pending = _lastAttempted;
    if (!_replayed && pending != null) {
      _replayed = true;
      add(const NearbyRetried());
      return;
    }
    _replayed = false;
    emit(state.copyWith(loading: false, error: AppError.from(event.error)));
  }

  Future<void> _send(NearbyRequested event, Emitter<NearbyState> emit) async {
    final issue = ++_issued;
    emit(state.copyWith(loading: true, clearError: true));
    final double lat;
    final double lon;
    if (event.lat == null || event.lon == null) {
      try {
        final position = await LocationService.instance.currentPosition();
        lat = position.latitude;
        lon = position.longitude;
      } on Object catch (e) {
        if (issue != _issued) return;
        emit(state.copyWith(loading: false, error: AppError.from(e)));
        return;
      }
      if (issue != _issued) return;
    } else {
      lat = event.lat!;
      lon = event.lon!;
    }
    _lastOrigin = (lat: lat, lon: lon);
    // Cold start only: paint the last answer for this spot while the query is
    // in flight, so the first screen isn't empty for a round trip. Never once
    // stations are up — a pan must not flash the previous session's list over
    // what the rider is already looking at.
    if (state.stations.isEmpty) {
      final cached = _cache.load(lat, lon);
      if (cached.isNotEmpty) emit(state.copyWith(stations: cached));
    }
    _attachStream();
    _queries?.add(NearQuery(lat: lat, lon: lon, radius: event.radius));
  }

  void _attachStream() {
    if (_queries != null) return;
    final queries = StreamController<NearQuery>();
    _queries = queries;
    _responses = _repository
        .near(queries.stream)
        .listen(
          (stations) => add(NearbyStationsReceived(stations)),
          onError: (Object error) => add(NearbyStreamFailed(error)),
          onDone: _detachStream,
        );
  }

  void _detachStream() {
    final responses = _responses;
    final queries = _queries;
    _responses = null;
    _queries = null;
    unawaited(responses?.cancel());
    unawaited(queries?.close());
  }

  @override
  Future<void> close() {
    _detachStream();
    return super.close();
  }
}
