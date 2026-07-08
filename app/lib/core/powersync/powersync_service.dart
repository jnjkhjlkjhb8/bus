import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/http/http_client.dart';
import 'package:wheres_the_car/core/powersync/local_db.dart';

const String _envPowersyncUrl = String.fromEnvironment(
  'POWERSYNC_URL',
);

const _schema = Schema([
  Table('bus_stops', [
    Column.text('stop_uid'),
    Column.text('stop_name'),
    Column.real('lat'),
    Column.real('lon'),
    Column.text('city'),
  ]),
  Table('mrt_stations', [
    Column.text('station_id'),
    Column.text('station_name'),
    Column.text('lines'),
    Column.real('lat'),
    Column.real('lon'),
  ]),
  Table('tra_stations', [
    Column.text('station_id'),
    Column.text('station_name'),
    Column.real('lat'),
    Column.real('lon'),
  ]),
  Table('thsr_stations', [
    Column.text('station_id'),
    Column.text('station_name'),
    Column.real('lat'),
    Column.real('lon'),
  ]),
  Table('mrt_journey_matrix', [
    Column.text('from_station_id'),
    Column.text('to_station_id'),
    Column.text('system'),
    Column.integer('fare_nt'),
    Column.integer('travel_time_min'),
  ]),
  Table('mrt_schedule', [
    Column.text('station_id'),
    Column.text('lineid'),
    Column.text('destinationstaionid'),
    Column.integer('serviceday'),
    Column.text('first_train_time'),
    Column.text('last_train_time'),
  ]),
]);

class PowerSyncService implements LocalDb {
  PowerSyncService._();
  static final PowerSyncService instance = PowerSyncService._();
  late final PowerSyncDatabase _db;
  bool _initialized = false;
  String? _lastSyncError;
  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    _db = PowerSyncDatabase(
      schema: _schema,
      path: p.join(dir.path, 'bus_local.db'),
    );
    await _db.initialize();
    _db.statusStream.listen((status) {
      final error = status.downloadError ?? status.uploadError;
      if (error == null) {
        _lastSyncError = null;
        return;
      }
      if (error.toString() == _lastSyncError) return;
      _lastSyncError = error.toString();
      CrashReporter.record(error);
    });
    if (_envPowersyncUrl.isNotEmpty) {
      try {
        final creds = await _NoopConnector().fetchCredentials();
        if (creds != null) {
          await _db.connect(connector: _NoopConnector());
        }
      } on Object catch (e, s) {
        CrashReporter.record(e, s);
        if (kDebugMode) {
          debugPrint(
            '[PowerSync] Init: failed to fetch credentials, running offline',
          );
        }
      }
    }
    _initialized = true;
  }

  PowerSyncDatabase get db {
    assert(_initialized, 'PowerSyncService.init() must be called before db');
    return _db;
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final result = await db.getAll(sql, parameters);
    // Detach rows from the sqlite ResultSet so callers hold plain maps.
    return [for (final row in result) Map<String, dynamic>.of(row)];
  }

  Future<void> close() async {
    if (_initialized) {
      await _db.close();
      _initialized = false;
    }
  }
}

class _NoopConnector extends PowerSyncBackendConnector {
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    if (_envPowersyncUrl.isEmpty) return null;
    try {
      final res = await HttpClient.instance.dio.get<Map<String, dynamic>>(
        '/api/token/powersync',
      );
      final token = res.data?['token'] as String?;
      if (token == null) return null;
      return PowerSyncCredentials(endpoint: _envPowersyncUrl, token: token);
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
      return null;
    }
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    if (kDebugMode) debugPrint('[PowerSync] uploadData (no-op)');
  }
}
