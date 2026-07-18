import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/generated/bike.pbgrpc.dart';
import 'package:wheres_the_car/data/models/bike_models.dart';

class BikeRepository {
  BikeRepository({Bike_ServiceClient? client}) : _client = client;

  static final BikeRepository instance = BikeRepository();

  Bike_ServiceClient? _client;
  Bike_ServiceClient get _grpc => _client ??= GrpcClient.instance.bike;

  Future<BikeStationInfo> stationStatic(String stationUid) async {
    final s = await _grpc.static(Bike_request(stationUID: stationUid));
    return BikeStationInfo(
      name: s.name,
      capacity: s.capacity,
      lat: double.tryParse(s.lat) ?? 0,
      lon: double.tryParse(s.lon) ?? 0,
    );
  }

  /// Server-streaming: emits decoded availability updates until cancelled.
  Stream<BikeAvailability> stationEta(String stationUid) => _grpc
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
