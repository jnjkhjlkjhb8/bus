import 'package:flutter/material.dart' show ThemeMode;
import 'package:wheres_the_car/core/storage/hive_store.dart';

/// Key-value backing store for [SettingsRepository].
///
/// The real implementation reads and writes the Hive settings box; tests
/// inject an in-memory map so no box needs opening.
abstract interface class SettingsStore {
  Object? get(String key, {Object? defaultValue});
  Future<void> put(String key, Object? value);
  bool get ready;
}

/// Reads and writes user preferences persisted in the settings box.
///
/// Features depend on this repository instead of reaching [HiveStore]
/// directly, keeping the storage engine behind the data layer. The setting
/// keys and defaults mirror the ones previously owned by [HiveStore].
class SettingsRepository {
  SettingsRepository({SettingsStore? store})
    : _store = store ?? const _HiveSettingsStore();

  static final SettingsRepository instance = SettingsRepository();

  final SettingsStore _store;

  bool _boolValue(String key, {required bool defaultValue}) =>
      _store.get(key, defaultValue: defaultValue) as bool? ?? defaultValue;

  bool get liveActivityEnabled =>
      _boolValue('live_activity_enabled', defaultValue: true);
  set liveActivityEnabled(bool value) =>
      _store.put('live_activity_enabled', value);

  bool get navigationLocationEnabled =>
      _boolValue('navigation_location_enabled', defaultValue: true);
  set navigationLocationEnabled(bool value) =>
      _store.put('navigation_location_enabled', value);

  bool get devModeEnabled =>
      _boolValue('dev_mode_enabled', defaultValue: false);
  set devModeEnabled(bool value) => _store.put('dev_mode_enabled', value);

  bool get largeText => _boolValue('large_text', defaultValue: false);
  set largeText(bool value) => _store.put('large_text', value);

  /// Persisted appearance preference: 'system', 'light', or 'dark'.
  /// Guarded on [SettingsStore.ready] so it is safe to read before the box
  /// opens (the pre-init splash reads it and must not throw).
  String get appearanceMode => _store.ready
      ? (_store.get('appearance_mode', defaultValue: 'system') as String? ??
            'system')
      : 'system';
  set appearanceMode(String value) => _store.put('appearance_mode', value);

  ThemeMode get themeMode => switch (appearanceMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  bool get pushEnabled => _boolValue('push_enabled', defaultValue: true);
  set pushEnabled(bool value) => _store.put('push_enabled', value);

  bool get analyticsEnabled =>
      _boolValue('analytics_enabled', defaultValue: true);
  set analyticsEnabled(bool value) => _store.put('analytics_enabled', value);

  bool get crashlyticsEnabled =>
      _boolValue('crashlytics_enabled', defaultValue: true);
  set crashlyticsEnabled(bool value) =>
      _store.put('crashlytics_enabled', value);

  bool get performanceEnabled =>
      _boolValue('performance_enabled', defaultValue: true);
  set performanceEnabled(bool value) =>
      _store.put('performance_enabled', value);

  List<String> get favMetroStations => List<String>.from(
    _store.get('fav_metro_stations', defaultValue: const <String>[]) as List? ??
        const <String>[],
  );
  set favMetroStations(List<String> list) =>
      _store.put('fav_metro_stations', list);

  /// Set of alert message keys the user has already read.
  Set<String> readAlerts() {
    if (!_store.ready) return {};
    final list =
        _store.get('read_alerts', defaultValue: const <String>[]) as List? ??
        const <String>[];
    return {...list.cast<String>()};
  }

  Future<void> setReadAlerts(Set<String> read) {
    if (!_store.ready) return Future<void>.value();
    return _store.put('read_alerts', read.toList());
  }
}

/// Hive-backed [SettingsStore] over the shared settings box.
class _HiveSettingsStore implements SettingsStore {
  const _HiveSettingsStore();

  @override
  bool get ready => HiveStore.settingsReady;

  @override
  Object? get(String key, {Object? defaultValue}) =>
      HiveStore.settings.get(key, defaultValue: defaultValue);

  @override
  Future<void> put(String key, Object? value) =>
      HiveStore.settings.put(key, value);
}
