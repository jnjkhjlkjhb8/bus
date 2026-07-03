import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/generated/bus.pb.dart';
import 'package:wheres_the_car/data/generated/bus.pbgrpc.dart';

class BusRepository {
  const BusRepository._();
  static const instance = BusRepository._();
  Future<Resp_Bus_static> routeStatic(String subRouteUid) => GrpcClient
      .instance
      .busRoute
      .static(Bus_Ask_Route(subRouteUID: subRouteUid));

  Future<Resp_Bus_daily_timetable> routeDaily(String subRouteUid) => GrpcClient
      .instance
      .busRoute
      .daily(Bus_Ask_Route(subRouteUID: subRouteUid));

  /// Server-streaming: emits updated bus positions until the stream is
  /// cancelled.
  Stream<Resp_Bus_eta> routeEta(String subRouteUid) =>
      GrpcClient.instance.busRoute.eta(Bus_Ask_Route(subRouteUID: subRouteUid));

  /// Server-streaming: emits ETA data for buses serving [stationName] in
  /// [city]. The server expects the key formatted as `"city:stationName"`.
  Stream<Resp_Bus_eta> stationEta(String city, String stationName) => GrpcClient
      .instance
      .busStation
      .eta(Bus_Ask_Route(subRouteUID: '$city:$stationName'));

  Stream<Resp_Bus_eta> stationEtaKey(String key) =>
      GrpcClient.instance.busStation.eta(Bus_Ask_Route(subRouteUID: key));

  Future<Bus_StationGroup> stationGroup(String groupUid) => GrpcClient
      .instance
      .busStation
      .group(Bus_Ask_Route(subRouteUID: groupUid));
}
