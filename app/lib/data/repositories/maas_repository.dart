import 'package:grpc/grpc.dart';
import 'package:wheres_the_bus/core/grpc/grpc_client.dart';
import 'package:wheres_the_bus/data/generated/maas.pbgrpc.dart';
import 'package:wheres_the_bus/data/models/plan_models.dart';

/// One stage of a streamed plan. `complete` is false while the router is still
/// resolving map geometry: the routes are final, but a section may still have
/// an empty walk/transit path and draw as a straight line.
typedef PlanUpdate = ({PlanResult result, bool complete});

/// Why a plan failed, in terms the screen can explain. Transport codes stop
/// here: a rider is told the routing service did not answer, not `DEADLINE
/// _EXCEEDED`.
enum PlanFailureKind {
  /// The router's own 20s ceiling, or the client deadline, ran out.
  timeout,

  /// Upstream routing is unreachable or refusing work (includes the per-caller
  /// TDX quota).
  unavailable,

  /// Routing answered, with no itinerary for this pair.
  noRoute,
  unknown,
}

class PlanFailure implements Exception {
  const PlanFailure(this.kind);

  final PlanFailureKind kind;

  @override
  String toString() => 'PlanFailure(${kind.name})';
}

class MaasRepository {
  MaasRepository({MaasServiceClient? client}) : _client = client;

  static final MaasRepository instance = MaasRepository();

  MaasServiceClient? _client;
  MaasServiceClient get _grpc => _client ??= GrpcClient.instance.maas;

  /// Streams the plan in stages — routes first, map geometry second — so the
  /// results list can appear without waiting for the OSRM walk paths.
  /// Cancelling the subscription cancels the RPC.
  Stream<PlanUpdate> planStream({
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
  }) {
    return _grpc
        .planStream(
          _request(
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
            transferMin: transferMin,
            transferMax: transferMax,
            firstMileMode: firstMileMode,
            firstMileTime: firstMileTime,
            lastMileMode: lastMileMode,
            lastMileTime: lastMileTime,
          ),
        )
        .map(
          (update) => (
            result: PlanResult.fromProto(update.plan),
            complete: update.complete,
          ),
        )
        .handleError(
          (Object error) => throw PlanFailure(_failureKind(error)),
        );
  }

  PlanFailureKind _failureKind(Object error) {
    if (error is! GrpcError) return PlanFailureKind.unknown;
    return switch (error.code) {
      StatusCode.deadlineExceeded => PlanFailureKind.timeout,
      StatusCode.notFound => PlanFailureKind.noRoute,
      StatusCode.unavailable ||
      StatusCode.resourceExhausted => PlanFailureKind.unavailable,
      _ => PlanFailureKind.unknown,
    };
  }

  // The unary `plan` RPC stays on the router for app versions already in the
  // wild, but nothing in this build calls it: every plan goes through the
  // streaming path above.

  MaasPlanRequest _request({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required String date,
    required String time,
    required bool arriveBy,
    required double gc,
    required List<int> transitModes,
    required int top,
    required int transferMin,
    required int transferMax,
    required int firstMileMode,
    required int firstMileTime,
    required int lastMileMode,
    required int lastMileTime,
  }) {
    return MaasPlanRequest(
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
    );
  }
}
