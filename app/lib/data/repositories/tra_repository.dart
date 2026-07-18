import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/data/decoders/tra_decoder.dart';
import 'package:wheres_the_car/data/generated/tra.pbgrpc.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';

class TraRepository {
  TraRepository({
    TRA_timetable_serviceClient? timetableClient,
    TRA_Detain_serviceClient? detainClient,
  }) : _timetableClient = timetableClient,
       _detainClient = detainClient;

  static final TraRepository instance = TraRepository();

  TRA_timetable_serviceClient? _timetableClient;
  TRA_timetable_serviceClient get _timetable =>
      _timetableClient ??= GrpcClient.instance.traTimetable;

  TRA_Detain_serviceClient? _detainClient;
  TRA_Detain_serviceClient get _detain =>
      _detainClient ??= GrpcClient.instance.traDetain;

  Future<List<TraTimetableItem>> timetable(
    String date,
    String originId,
    String destId,
  ) async {
    final result = await _timetable.timetable(
      ask_route(
        date: date,
        originStationId: originId,
        destinationStationId: destId,
      ),
    );
    return TraDecoder.instance.decodeTimetable(result);
  }

  /// Adult/full fare for an origin→destination pair. `ask_staiton` carries the
  /// pair across its two string fields — station_id is the origin, date is the
  /// destination id — matching the router's Fare handler (TRA fares are per
  /// O/D, not per date). The router resolves station names to ids, so plain
  /// station names are valid arguments too.
  Future<TraFare> fare(String originId, String destId) async {
    final result = await _timetable.fare(
      ask_staiton(stationId: originId, date: destId),
    );
    return TraDecoder.instance.decodeFare(result);
  }

  /// Server-streaming: emits decoded delay data (trainNo → delay minutes) for
  /// trains on the [originId]→[destId] segment on [date].
  Stream<Map<String, int>> delay(
    String date,
    String originId,
    String destId,
  ) => _timetable
      .delay(
        ask_route(
          date: date,
          originStationId: originId,
          destinationStationId: destId,
        ),
      )
      .map(
        (resp) => Map<String, int>.from(
          TraDecoder.instance.decodeDelayMap(resp.data),
        ),
      );

  Future<List<TraStopTime>> stops(String date, String trainNo) async {
    final result = await _detain.stops(
      ask_detain(date: date, trainno: trainNo),
    );
    return TraDecoder.instance.decodeStops(result);
  }
}
