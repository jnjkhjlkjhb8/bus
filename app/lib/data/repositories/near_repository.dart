import 'dart:async';

import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/generated/near.pb.dart';

class NearRepository {
  const NearRepository._();
  static const instance = NearRepository._();

  /// Bidirectional-streaming passthrough. Callers control the request stream
  /// and receive one [resp_near] per request sent.
  Stream<resp_near> near(Stream<Ask_Near> requests) =>
      GrpcClient.instance.near.near(requests);

  /// Convenience: sends a single nearby-station query and returns the stream.
  ///
  /// [lat] / [lon] — WGS-84 coordinates.
  /// [radius] — search radius in metres.
  Stream<resp_near> nearOnce(double lat, double lon, int radius) {
    final ctrl = StreamController<Ask_Near>()
      ..add(
        Ask_Near(
          positionLat: lat,
          positionLon: lon,
          radius: radius,
        ),
      );
    unawaited(ctrl.close());
    return near(ctrl.stream);
  }
}
