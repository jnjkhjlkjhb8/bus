import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/generated/thsr.pb.dart';

class ThsrRepository {
  const ThsrRepository._();
  static const instance = ThsrRepository._();

  Future<thsa_fare> fare(String date, String originId, String destId) =>
      GrpcClient.instance.thsr.fare(
        Ask_Thsr(
          date: date,
          originStationId: originId,
          destinationStationId: destId,
        ),
      );

  Future<thsr_timetables> timetable(
    String date,
    String originId,
    String destId,
  ) => GrpcClient.instance.thsr.timetable(
    Ask_Thsr(
      date: date,
      originStationId: originId,
      destinationStationId: destId,
    ),
  );

  Future<thsr_stoptimes> stops(String date, String trainNo) => GrpcClient
      .instance
      .thsrDetain
      .stops(thsr_ask_detain(date: date, trainno: trainNo));
}
