import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/decoders/mrt_decoder.dart';
import 'package:wheres_the_car/data/generated/mrt.pb.dart';
import 'package:wheres_the_car/data/models/metro_models.dart';

class MrtRepository {
  const MrtRepository._();
  static const instance = MrtRepository._();

  /// Server-streaming: emits decoded MRT arrival estimates until cancelled.
  ///
  /// [system] — metro operator code, e.g. `'TRTC'` (台北捷運).
  /// [stationId] — station identifier within the system.
  Stream<MetroLiveArrival> eta(String system, String stationId) => GrpcClient
      .instance
      .mrt
      .eta(Ask_mrt(system: system, stationID: stationId))
      .map((resp) => MrtDecoder.instance.decodeEta(resp.data));
}
