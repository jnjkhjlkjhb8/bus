import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/core/powersync/local_db.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/data/decoders/tra_decoder.dart';
import 'package:wheres_the_car/data/generated/tra.pb.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';

class TraRepository {
  TraRepository({LocalDb? localDb}) : _localDb = localDb;

  static final TraRepository instance = TraRepository();

  // Resolved lazily so tests that never touch the local DB can construct the
  // repository without initializing PowerSync.
  LocalDb? _localDb;
  LocalDb get _db => _localDb ??= PowerSyncService.instance;

  /// Server-streaming: emits the decoded live departure/arrival board for
  /// [stationId] on [date] (format `'yyyy-MM-dd'`).
  Stream<List<TraLiveBoardItem>> liveBoard(String stationId, String date) =>
      GrpcClient.instance.traStation
          .live_board(ask_staiton(stationId: stationId, date: date))
          .map(
            (resp) => TraDecoder.instance.decodeLiveBoard(resp.data),
          );

  Future<List<TraTimetableItem>> timetable(
    String date,
    String originId,
    String destId,
  ) async {
    final result = await GrpcClient.instance.traTimetable.timetable(
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
  Future<TraFareItem> fare(String stationId, String date) => GrpcClient
      .instance
      .traTimetable
      .fare(ask_staiton(stationId: stationId, date: date));

  /// Server-streaming: emits decoded delay data (trainNo → delay minutes) for
  /// trains on the [originId]→[destId] segment on [date].
  Stream<Map<String, int>> delay(
    String date,
    String originId,
    String destId,
  ) => GrpcClient.instance.traTimetable
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
    final result = await GrpcClient.instance.traDetain.stops(
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
