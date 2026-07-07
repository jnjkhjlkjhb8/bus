import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/decoders/bus_decoder.dart';
import 'package:wheres_the_car/data/generated/bus.pb.dart';
import 'package:wheres_the_car/data/generated/bus.pbgrpc.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';

class BusRepository {
  const BusRepository._();
  static const instance = BusRepository._();

  Future<BusRouteViewModel> routeStatic(String subRouteUid) async {
    final resp = await GrpcClient.instance.busRoute
        .static(Bus_Ask_Route(subRouteUID: subRouteUid));
    return BusDecoder.instance.decodeStatic(resp.data);
  }

  Future<BusDailyTimetable> routeDaily(String subRouteUid) async {
    final resp = await GrpcClient.instance.busRoute
        .daily(Bus_Ask_Route(subRouteUID: subRouteUid));
    return BusDecoder.instance.decodeDaily(resp.data);
  }

  /// Server-streaming: emits decoded route ETAs until the stream is cancelled.
  Stream<List<BusStopEtaViewModel>> routeEta(String subRouteUid) =>
      GrpcClient.instance.busRoute
          .eta(Bus_Ask_Route(subRouteUID: subRouteUid))
          .map((resp) => BusDecoder.instance.decodeRouteEta(resp.data));

  /// Server-streaming: emits station-group ETA data. [city] may be empty; the
  /// server resolves it from the group when omitted.
  Stream<Resp_Bus_station_eta> stationEta(String city, String groupUid) =>
      GrpcClient.instance.busStation
          .eta(Bus_Ask_StationGroup(city: city, groupUid: groupUid));

  Future<Bus_StationGroup> stationGroup(String groupUid) => GrpcClient
      .instance
      .busStation
      .group(Bus_Ask_StationGroup(groupUid: groupUid));
}
