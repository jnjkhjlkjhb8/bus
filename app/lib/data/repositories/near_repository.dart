import 'dart:async';

import 'package:wheres_the_bus/core/grpc/grpc_client.dart';
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
