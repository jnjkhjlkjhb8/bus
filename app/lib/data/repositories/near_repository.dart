import 'dart:async';

import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/decoders/near_decoder.dart';
import 'package:wheres_the_car/data/generated/near.pb.dart';
import 'package:wheres_the_car/data/models/near_models.dart';

// Nearby domain types live in data/models/near_models.dart; re-exported so
// feature callers keep resolving them through the repository.
export 'package:wheres_the_car/data/models/near_models.dart'
    show NearQuery, NearStationType, NearStationViewModel;

class NearRepository {
  const NearRepository._();
  static const instance = NearRepository._();

  /// Bidirectional-streaming query. Callers control the request stream and
  /// receive one decoded station list per [NearQuery] sent.
  Stream<List<NearStationViewModel>> near(Stream<NearQuery> queries) {
    final requests = queries.map(
      (q) => Ask_Near(
        positionLat: q.lat,
        positionLon: q.lon,
        radius: q.radius,
      ),
    );
    return GrpcClient.instance.near
        .near(requests)
        .map(NearDecoder.instance.decode);
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
