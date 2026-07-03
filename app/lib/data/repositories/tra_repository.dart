import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/generated/tra.pb.dart';

class TraRepository {
  const TraRepository._();
  static const instance = TraRepository._();

  /// Server-streaming: emits live departure/arrival board for [stationId]
  /// on [date] (format `'yyyy-MM-dd'`).
  Stream<Resp_tra_live_board> liveBoard(String stationId, String date) =>
      GrpcClient.instance.traStation.live_board(
        ask_staiton(stationId: stationId, date: date),
      );
  Future<tra_timetables> timetable(
    String date,
    String originId,
    String destId,
  ) => GrpcClient.instance.traTimetable.timetable(
    ask_route(
      date: date,
      originStationId: originId,
      destinationStationId: destId,
    ),
  );

  /// Fare query. [stationId] is expected in `'originId:destId'` format when
  /// querying an O/D pair.
  Future<TraFareItem> fare(String stationId, String date) => GrpcClient
      .instance
      .traTimetable
      .fare(ask_staiton(stationId: stationId, date: date));

  /// Server-streaming: emits delay data for trains on the [originId]→[destId]
  /// segment on [date].
  Stream<Resp_tra_delay> delay(
    String date,
    String originId,
    String destId,
  ) => GrpcClient.instance.traTimetable.delay(
    ask_route(
      date: date,
      originStationId: originId,
      destinationStationId: destId,
    ),
  );
  Future<tra_stoptimes> stops(String date, String trainNo) => GrpcClient
      .instance
      .traDetain
      .stops(ask_detain(date: date, trainno: trainNo));

  /// Server-streaming: emits delay updates for a specific [trainNo].
  Stream<Resp_tra_delay> trainDelay(String date, String trainNo) => GrpcClient
      .instance
      .traDetain
      .delay(ask_detain(date: date, trainno: trainNo));
}
