import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/core/powersync/local_db.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/data/decoders/mrt_decoder.dart';
import 'package:wheres_the_car/data/generated/mrt.pbgrpc.dart';
import 'package:wheres_the_car/data/models/journey_info.dart';
import 'package:wheres_the_car/data/models/metro_models.dart';

class MrtRepository {
  MrtRepository({Mrt_ServiceClient? client, LocalDb? localDb})
    : _client = client,
      _localDb = localDb;

  static final MrtRepository instance = MrtRepository();

  // Resolved lazily so tests that never touch the local DB can construct the
  // repository without initializing PowerSync.
  LocalDb? _localDb;
  LocalDb get _db => _localDb ??= PowerSyncService.instance;

  Mrt_ServiceClient? _client;
  Mrt_ServiceClient get _grpc => _client ??= GrpcClient.instance.mrt;

  /// Server-streaming: emits decoded MRT arrival estimates until cancelled.
  ///
  /// [system] — metro operator code, e.g. `'TRTC'` (台北捷運).
  /// [stationId] — station identifier within the system.
  Stream<MetroLiveArrival> eta(String system, String stationId) => _grpc
      .eta(Ask_mrt(system: system, stationID: stationId))
      .map((resp) => MrtDecoder.instance.decodeEta(resp.data));

  /// First/last-train schedule rows for [stationId] from the synced mirror.
  Future<List<MetroScheduleEntry>> schedule(String stationId) async {
    final rows = await _db.getAll(
      'SELECT destinationstaionid, first_train_time, last_train_time '
      'FROM mrt_schedule WHERE station_id = ?',
      [stationId],
    );
    return [for (final row in rows) MetroScheduleEntry.fromRow(row)];
  }

  /// Fare + travel-time matrix from [stationId], keyed by destination id.
  Future<Map<String, JourneyInfo>> journeyMatrix(String stationId) async {
    final rows = await _db.getAll(
      'SELECT to_station_id, fare_nt, travel_time_min '
      'FROM mrt_journey_matrix WHERE from_station_id = ?',
      [stationId],
    );
    return {
      for (final row in rows)
        row['to_station_id'] as String: JourneyInfo.fromRow(row),
    };
  }
}
