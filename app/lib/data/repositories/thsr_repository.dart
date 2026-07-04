import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/decoders/thsr_decoder.dart';
import 'package:wheres_the_car/data/generated/thsr.pb.dart';
import 'package:wheres_the_car/data/models/thsr_models.dart';

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

  Future<List<ThsrTimetableItem>> timetable(
    String date,
    String originId,
    String destId,
  ) async {
    final result = await GrpcClient.instance.thsr.timetable(
      Ask_Thsr(
        date: date,
        originStationId: originId,
        destinationStationId: destId,
      ),
    );
    return ThsrDecoder.instance.decodeTimetable(result);
  }

  Future<List<ThsrStopTime>> stops(String date, String trainNo) async {
    final result = await GrpcClient.instance.thsrDetain.stops(
      thsr_ask_detain(date: date, trainno: trainNo),
    );
    return ThsrDecoder.instance.decodeStopTimes(result);
  }
}
