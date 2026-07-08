import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/generated/maas.pbgrpc.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';

class MaasRepository {
  MaasRepository({MaasServiceClient? client}) : _client = client;

  static final MaasRepository instance = MaasRepository();

  MaasServiceClient? _client;
  MaasServiceClient get _grpc => _client ??= GrpcClient.instance.maas;

  Future<PlanResult> plan({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required String date,
    required String time,
    bool arriveBy = false,
    double gc = 0.0,
    List<int> transitModes = const [3, 4, 5, 6, 7, 8, 9],
    int top = 5,
    int transferMin = 15,
    int transferMax = 60,
    int firstMileMode = 0,
    int firstMileTime = 10,
    int lastMileMode = 0,
    int lastMileTime = 10,
  }) async {
    final response = await _grpc.plan(
      MaasPlanRequest(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: toLat,
        toLon: toLon,
        date: date,
        time: time,
        arriveBy: arriveBy,
        gc: gc,
        transitModes: transitModes,
        top: top,
        transferTimeMin: transferMin,
        transferTimeMax: transferMax,
        firstMileMode: firstMileMode,
        firstMileTime: firstMileTime,
        lastMileMode: lastMileMode,
        lastMileTime: lastMileTime,
      ),
    );
    return PlanResult.fromProto(response);
  }
}
