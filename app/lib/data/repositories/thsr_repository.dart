import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/core/powersync/local_db.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/data/decoders/thsr_decoder.dart';
import 'package:wheres_the_car/data/generated/thsr.pb.dart';
import 'package:wheres_the_car/data/models/thsr_models.dart';

class ThsrRepository {
  ThsrRepository({LocalDb? localDb}) : _localDb = localDb;

  static final ThsrRepository instance = ThsrRepository();

  // Resolved lazily so tests that never touch the local DB can construct the
  // repository without initializing PowerSync.
  LocalDb? _localDb;
  LocalDb get _db => _localDb ??= PowerSyncService.instance;

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

  /// Resolves a THSR station name to its id from the synced station table, or
  /// null when the name is unknown. Reads the offline PowerSync mirror.
  Future<String?> stationId(String name) async {
    final rows = await _db.getAll(
      'SELECT station_id FROM thsr_stations WHERE station_name = ? LIMIT 1',
      [name],
    );
    if (rows.isEmpty) return null;
    return rows.first['station_id'] as String?;
  }
}
