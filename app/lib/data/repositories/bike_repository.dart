import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/generated/bike.pb.dart';

class BikeRepository {
  const BikeRepository._();
  static const instance = BikeRepository._();

  Future<Bike_static> stationStatic(String stationUid) =>
      GrpcClient.instance.bike.static(Bike_request(stationUID: stationUid));

  /// Server-streaming: emits live availability updates until cancelled.
  Stream<Resp_Bike_eta> stationEta(String stationUid) =>
      GrpcClient.instance.bike.eta(Bike_request(stationUID: stationUid));
}
