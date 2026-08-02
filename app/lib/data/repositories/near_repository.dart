import 'dart:async';
import 'dart:math' as math;

import 'package:wheres_the_bus/core/grpc/grpc_client.dart';
import 'package:wheres_the_bus/core/storage/hive_store.dart';
import 'package:wheres_the_bus/data/decoders/near_decoder.dart';
import 'package:wheres_the_bus/data/generated/near.pbgrpc.dart';
import 'package:wheres_the_bus/data/models/near_models.dart';

// Nearby domain types live in data/models/near_models.dart; re-exported so
// feature callers keep resolving them through the repository.
export 'package:wheres_the_bus/data/models/near_models.dart'
    show NearQuery, NearStationType, NearStationViewModel;

class NearRepository {
  NearRepository({Near_Station_ServiceClient? client}) : _client = client;

  static final NearRepository instance = NearRepository();

  Near_Station_ServiceClient? _client;
  Near_Station_ServiceClient get _grpc => _client ??= GrpcClient.instance.near;

  /// Bidirectional-streaming query. Callers control the request stream and
  /// receive decoded station lists in the order the router answers them.
  ///
  /// Not one response per request: the router drops a query that a newer one
  /// superseded before it was picked up, so callers must treat each response as
  /// the current answer rather than pairing it with a specific request.
  Stream<List<NearStationViewModel>> near(Stream<NearQuery> queries) {
    final requests = queries.map(
      (q) => Ask_Near(
        positionLat: q.lat,
        positionLon: q.lon,
        radius: q.radius,
      ),
    );
    return _grpc.near(requests).map(NearDecoder.instance.decode);
  }

  /// Convenience: sends a single nearby-station query and returns the decoded
  /// station list stream.
  ///
  /// [lat] / [lon] — WGS-84 coordinates.
  /// [radius] — search radius in metres.
  Stream<List<NearStationViewModel>> nearOnce(
    double lat,
    double lon,
    int radius,
  ) {
    final ctrl = StreamController<NearQuery>()
      ..add(NearQuery(lat: lat, lon: lon, radius: radius));
    unawaited(ctrl.close());
    return near(ctrl.stream);
  }
}

/// The last nearby answer, kept on disk so a cold start from the place the
/// rider was last at paints stations immediately instead of after the round
/// trip (400 ms at best, seconds when the router misses its cache).
///
/// Always superseded: the live query is issued in the same breath and its
/// result overwrites this one, so the cache only has to be plausible, not
/// current. Walking times and distances shift by metres when the fix moves
/// within [_maxDriftMeters]; station positions only change at the 03:30 load.
class NearCache {
  const NearCache._();
  static const instance = NearCache._();

  static const _key = 'last_nearby';

  /// Beyond this the stored list is about somewhere else, not about here.
  static const _maxDriftMeters = 150.0;

  /// A week-old list is still a fair guess at what is around a coordinate, and
  /// it is on screen for the length of one round trip.
  static const _maxAge = Duration(days: 7);

  /// How long a stored entry suppresses rewrites from the same place.
  static const _rewriteInterval = Duration(minutes: 10);

  List<NearStationViewModel> load(double lat, double lon) {
    if (!HiveStore.settingsReady) return const [];
    final raw = HiveStore.settings.get(_key);
    if (raw is! Map) return const [];
    final savedAt = raw['savedAt'];
    final originLat = raw['lat'];
    final originLon = raw['lon'];
    if (savedAt is! int || originLat is! num || originLon is! num) {
      return const [];
    }
    final age = DateTime.now().millisecondsSinceEpoch - savedAt;
    if (age < 0 || age > _maxAge.inMilliseconds) return const [];
    if (_metresBetween(lat, lon, originLat.toDouble(), originLon.toDouble()) >
        _maxDriftMeters) {
      return const [];
    }
    final stations = raw['stations'];
    if (stations is! List) return const [];
    return stations
        .whereType<Map<dynamic, dynamic>>()
        .map(_fromMap)
        .whereType<NearStationViewModel>()
        .toList(growable: false);
  }

  Future<void> save(
    double lat,
    double lon,
    List<NearStationViewModel> stations,
  ) async {
    if (!HiveStore.settingsReady) return;
    // Every settled pan produces a response, and each write serialises the
    // whole list. A rider working around one neighbourhood gets one write, not
    // one per nudge; the age bound keeps the entry from going stale in place.
    if (_savedRecentlyNear(lat, lon)) return;
    await HiveStore.settings.put(_key, {
      'lat': lat,
      'lon': lon,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'stations': stations.map(_toMap).toList(growable: false),
    });
  }

  bool _savedRecentlyNear(double lat, double lon) {
    final raw = HiveStore.settings.get(_key);
    if (raw is! Map) return false;
    final savedAt = raw['savedAt'];
    final originLat = raw['lat'];
    final originLon = raw['lon'];
    if (savedAt is! int || originLat is! num || originLon is! num) return false;
    final age = DateTime.now().millisecondsSinceEpoch - savedAt;
    if (age < 0 || age > _rewriteInterval.inMilliseconds) return false;
    final drift = _metresBetween(
      lat,
      lon,
      originLat.toDouble(),
      originLon.toDouble(),
    );
    return drift < _maxDriftMeters;
  }

  Map<String, Object?> _toMap(NearStationViewModel s) => {
    'type': s.type.name,
    'id': s.stationId,
    'name': s.stationName,
    'lat': s.lat,
    'lon': s.lon,
    'walk': s.walkingMinutes,
    'dist': s.distanceMeters,
    'routed': s.routed,
  };

  NearStationViewModel? _fromMap(Map<dynamic, dynamic> map) {
    final type = NearStationType.values.where((t) => t.name == map['type']);
    final id = map['id'];
    final name = map['name'];
    final lat = map['lat'];
    final lon = map['lon'];
    if (type.isEmpty ||
        id is! String ||
        name is! String ||
        lat is! num ||
        lon is! num) {
      return null;
    }
    return NearStationViewModel(
      type: type.first,
      stationId: id,
      stationName: name,
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      walkingMinutes: (map['walk'] as num?)?.toInt() ?? 0,
      distanceMeters: (map['dist'] as num?)?.toInt() ?? 0,
      routed: map['routed'] as bool? ?? false,
    );
  }
}

/// Equirectangular approximation: exact enough at the ~150 m scale this is
/// compared against, and it costs one cosine instead of a haversine.
double _metresBetween(double lat1, double lon1, double lat2, double lon2) {
  const metresPerDegree = 111320.0;
  final dLat = (lat1 - lat2) * metresPerDegree;
  final dLon = (lon1 - lon2) * metresPerDegree * math.cos(lat1 * math.pi / 180);
  return math.sqrt(dLat * dLat + dLon * dLon);
}
