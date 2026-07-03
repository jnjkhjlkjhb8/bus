import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/generated/mrt.pb.dart';

class MrtRepository {
  const MrtRepository._();
  static const instance = MrtRepository._();

  /// Server-streaming: emits live MRT arrival estimates until cancelled.
  ///
  /// [system] — metro operator code, e.g. `'TRTC'` (台北捷運).
  /// [stationId] — station identifier within the system.
  Stream<Resp_Mrt_eta> eta(String system, String stationId) => GrpcClient
      .instance
      .mrt
      .eta(Ask_mrt(system: system, stationID: stationId));
}
