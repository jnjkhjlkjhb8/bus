import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/core/powersync/local_db.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/data/decoders/thsr_decoder.dart';
import 'package:wheres_the_car/data/generated/thsr.pbgrpc.dart';
import 'package:wheres_the_car/data/models/thsr_models.dart';

class ThsrRepository {
  ThsrRepository({
    Thsr_timetable_serviceClient? timetableClient,
    Thsr_Detain_serviceClient? detainClient,
    LocalDb? localDb,
  }) : _timetableClient = timetableClient,
       _detainClient = detainClient,
       _localDb = localDb;

  static final ThsrRepository instance = ThsrRepository();

  // Resolved lazily so tests that never touch the local DB can construct the
  // repository without initializing PowerSync.
  LocalDb? _localDb;
  LocalDb get _db => _localDb ??= PowerSyncService.instance;

  Thsr_timetable_serviceClient? _timetableClient;
  Thsr_timetable_serviceClient get _grpc =>
      _timetableClient ??= GrpcClient.instance.thsr;

  Thsr_Detain_serviceClient? _detainClient;
  Thsr_Detain_serviceClient get _detain =>
      _detainClient ??= GrpcClient.instance.thsrDetain;

  Future<thsa_fare> fare(String date, String originId, String destId) =>
      _grpc.fare(
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
