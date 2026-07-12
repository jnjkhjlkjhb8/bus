import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/core/powersync/local_db.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/data/decoders/tra_decoder.dart';
import 'package:wheres_the_car/data/generated/tra.pbgrpc.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';

class TraRepository {
  TraRepository({
    TRA_timetable_serviceClient? timetableClient,
    TRA_Detain_serviceClient? detainClient,
    LocalDb? localDb,
  }) : _timetableClient = timetableClient,
       _detainClient = detainClient,
       _localDb = localDb;

  static final TraRepository instance = TraRepository();

  // Resolved lazily so tests that never touch the local DB can construct the
  // repository without initializing PowerSync.
  LocalDb? _localDb;
  LocalDb get _db => _localDb ??= PowerSyncService.instance;

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

  /// Fare query. [stationId] is expected in `'originId:destId'` format when
  /// querying an O/D pair.
  Future<TraFare> fare(String stationId, String date) async {
    final result = await _timetable.fare(
      ask_staiton(stationId: stationId, date: date),
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

  /// Resolves a TRA station name to its id from the synced station table, or
  /// null when the name is unknown. Reads the offline PowerSync mirror.
  Future<String?> stationId(String name) async {
    final rows = await _db.getAll(
      'SELECT station_id FROM tra_stations WHERE station_name = ? LIMIT 1',
      [name],
    );
    if (rows.isEmpty) return null;
    return rows.first['station_id'] as String?;
  }
}
