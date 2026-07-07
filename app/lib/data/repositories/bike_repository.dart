import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/generated/bike.pb.dart';
import 'package:wheres_the_car/data/models/bike_models.dart';

class BikeRepository {
  const BikeRepository._();
  static const instance = BikeRepository._();

  Future<BikeStationInfo> stationStatic(String stationUid) async {
    final s = await GrpcClient.instance.bike
        .static(Bike_request(stationUID: stationUid));
    return BikeStationInfo(name: s.name, capacity: s.capacity);
  }

  /// Server-streaming: emits decoded availability updates until cancelled.
  Stream<BikeAvailability> stationEta(String stationUid) => GrpcClient
      .instance
      .bike
      .eta(Bike_request(stationUID: stationUid))
      .map((resp) {
        final e = resp.data;
        return BikeAvailability(
          generalBikes: e.generalBikes,
          electricBikes: e.electricBikes,
          returnDocks: e.availableReturnBikes,
        );
      });
}
