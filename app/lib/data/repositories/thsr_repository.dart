import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/decoders/thsr_decoder.dart';
import 'package:wheres_the_car/data/generated/thsr.pbgrpc.dart';
import 'package:wheres_the_car/data/models/thsr_models.dart';

class ThsrRepository {
  ThsrRepository({
    Thsr_timetable_serviceClient? timetableClient,
    Thsr_Detain_serviceClient? detainClient,
  }) : _timetableClient = timetableClient,
       _detainClient = detainClient;

  static final ThsrRepository instance = ThsrRepository();

  Thsr_timetable_serviceClient? _timetableClient;
  Thsr_timetable_serviceClient get _grpc =>
      _timetableClient ??= GrpcClient.instance.thsr;

  Thsr_Detain_serviceClient? _detainClient;
  Thsr_Detain_serviceClient get _detain =>
      _detainClient ??= GrpcClient.instance.thsrDetain;

  Future<ThsrFare> fare(String date, String originId, String destId) async {
    final result = await _grpc.fare(
      Ask_Thsr(
        date: date,
        originStationId: originId,
        destinationStationId: destId,
      ),
    );
    return ThsrDecoder.instance.decodeFare(result);
  }

  Future<List<ThsrTimetableItem>> timetable(
    String date,
    String originId,
    String destId,
  ) async {
    final result = await _grpc.timetable(
      Ask_Thsr(
        date: date,
        originStationId: originId,
        destinationStationId: destId,
      ),
    );
    return ThsrDecoder.instance.decodeTimetable(result);
  }

  Future<List<ThsrStopTime>> stops(String date, String trainNo) async {
    final result = await _detain.stops(
      thsr_ask_detain(date: date, trainno: trainNo),
    );
    return ThsrDecoder.instance.decodeStopTimes(result);
  }
}
