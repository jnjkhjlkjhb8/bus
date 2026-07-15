import 'dart:async';

import 'package:hive_ce_flutter/adapters.dart';

class HiveStore {
  HiveStore._();

  static const _boxLayout = 'board_layout';
  static const _boxFavRoutes = 'fav_routes';
  static const _boxFavorites = 'favorites';
  static const _boxSettings = 'settings';
  static const _boxRecents = 'recent_searches';
  static const _boxReminders = 'arrival_reminders';
  static const _boxSavedPlans = 'saved_plans';

  static Future<void>? _initFuture;

  /// Opens every Hive box the app reads from. Concurrent callers share the
  /// same in-flight [Future]. Unlike a plain memoized future, a failure is
  /// visible to every awaiter (the returned future rejects) and is *not*
  /// permanently cached (F13): the next call to [init] retries from
  /// scratch instead of silently reporting success while boxes stay
  /// unopened. [initBinding] exists only for tests, which point Hive at a
  /// directory manually and would otherwise hit `path_provider`'s missing
  /// platform channel via `Hive.initFlutter()`.
  static Future<void> init({Future<void> Function()? initBinding}) {
    final existing = _initFuture;
    if (existing != null) return existing;
    final future = _open(initBinding ?? Hive.initFlutter);
    _initFuture = future;
    unawaited(
      future.catchError((Object _, StackTrace _) {
        _initFuture = null;
      }),
    );
    return future;
  }

  static Future<void> _open(Future<void> Function() initBinding) async {
    await initBinding();
    await Future.wait([
      Hive.openBox<dynamic>(_boxLayout),
      Hive.openBox<dynamic>(_boxFavRoutes),
      Hive.openBox<dynamic>(_boxFavorites),
      Hive.openBox<dynamic>(_boxSettings),
      Hive.openBox<dynamic>(_boxRecents),
      Hive.openBox<dynamic>(_boxReminders),
      Hive.openBox<dynamic>(_boxSavedPlans),
    ]);
  }

  static Box<dynamic> get layout => Hive.box(_boxLayout);
  static Box<dynamic> get favRoutes => Hive.box(_boxFavRoutes);
  static Box<dynamic> get recents => Hive.box(_boxRecents);

  static List<Map<String, dynamic>> get recentSearches =>
      (recents.get('items', defaultValue: const <dynamic>[]) as List)
          .cast<Map<dynamic, dynamic>>()
          .map((m) => m.cast<String, dynamic>())
          .toList();

  static Future<void> addRecentSearch(Map<String, dynamic> item) async {
    final items = recentSearches
      ..removeWhere(
        (e) => e['uid'] == item['uid'] && e['type'] == item['type'],
      )
      ..insert(0, item);
    await recents.put('items', items.take(10).toList());
  }

  /// Recent rail train-number queries as `{system, trainNo}`, newest first.
  static List<Map<String, dynamic>> get recentTrainQueries =>
      (recents.get('train_queries', defaultValue: const <dynamic>[]) as List)
          .cast<Map<dynamic, dynamic>>()
          .map((m) => m.cast<String, dynamic>())
          .toList();

  static Future<void> addRecentTrainQuery(
    String system,
    String trainNo,
  ) async {
    final items = recentTrainQueries
      ..removeWhere(
        (e) => e['system'] == system && e['trainNo'] == trainNo,
      )
      ..insert(0, {'system': system, 'trainNo': trainNo});
    await recents.put('train_queries', items.take(6).toList());
  }

  static Box<dynamic> get savedPlans => Hive.box(_boxSavedPlans);
  static bool get savedPlansReady => Hive.isBoxOpen(_boxSavedPlans);

  /// Saved route snapshots as `{key, bytes, savedAt}`, newest first. `bytes`
  /// are the verbatim TDX proto bytes of a single route.
  static List<Map<String, dynamic>> get savedPlanEntries =>
      savedPlans.values
          .cast<Map<dynamic, dynamic>>()
          .map((m) => m.cast<String, dynamic>())
          .toList()
        ..sort(
          (a, b) => (b['savedAt'] as int? ?? 0).compareTo(
            a['savedAt'] as int? ?? 0,
          ),
        );

  static Future<void> putSavedPlan(String key, List<int> bytes) =>
      savedPlans.put(key, {
        'key': key,
        'bytes': bytes,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      });

  static Future<void> removeSavedPlan(String key) => savedPlans.delete(key);

  static Box<dynamic> get favorites => Hive.box(_boxFavorites);
  static bool get favoritesReady => Hive.isBoxOpen(_boxFavorites);
  static Box<dynamic> get settings => Hive.box(_boxSettings);
  static bool get settingsReady => Hive.isBoxOpen(_boxSettings);
  static bool get liveActivityEnabled =>
      settings.get('live_activity_enabled', defaultValue: true) as bool;

  static set liveActivityEnabled(bool v) =>
      settings.put('live_activity_enabled', v);

  static bool get devModeEnabled =>
      settings.get('dev_mode_enabled', defaultValue: false) as bool;

  static set devModeEnabled(bool v) => settings.put('dev_mode_enabled', v);

  static bool get largeText =>
      settings.get('large_text', defaultValue: false) as bool;

  static set largeText(bool v) => settings.put('large_text', v);

  static bool get pushEnabled =>
      settings.get('push_enabled', defaultValue: true) as bool;

  static set pushEnabled(bool value) => settings.put('push_enabled', value);

  static bool get analyticsEnabled =>
      settings.get('analytics_enabled', defaultValue: true) as bool;

  static set analyticsEnabled(bool value) =>
      settings.put('analytics_enabled', value);

  static bool get crashlyticsEnabled =>
      settings.get('crashlytics_enabled', defaultValue: true) as bool;

  static set crashlyticsEnabled(bool value) =>
      settings.put('crashlytics_enabled', value);

  static bool get performanceEnabled =>
      settings.get('performance_enabled', defaultValue: true) as bool;

  static set performanceEnabled(bool value) =>
      settings.put('performance_enabled', value);

  static List<String> get favMetroStations => List<String>.from(
    settings.get('fav_metro_stations', defaultValue: <String>[]) as List,
  );

  static set favMetroStations(List<String> list) =>
      settings.put('fav_metro_stations', list);

  // Local mirror of arrival reminders (routeUid -> { stopUid -> {id, exp} }) so
  // the bell survives navigation/restart — the server has no listReminders RPC
  // to read active reminders back.
  static bool get _remindersReady => Hive.isBoxOpen(_boxReminders);
  static Box<dynamic> get _reminders => Hive.box(_boxReminders);

  /// Active (non-expired) reminders for a route: stopUid -> reminderId.
  /// Expired entries are filtered on read rather than pruned on write.
  static Map<String, String> activeReminders(String routeUid) {
    if (!_remindersReady) return <String, String>{};
    final raw = _reminders.get(routeUid) as Map?;
    if (raw == null) return <String, String>{};
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final out = <String, String>{};
    raw.forEach((k, v) {
      final entry = (v as Map).cast<String, dynamic>();
      final exp = entry['exp'] as int?;
      if (exp != null && exp < nowMs) return;
      out[k as String] = entry['id'] as String;
    });
    return out;
  }

  static Future<void> putReminder(
    String routeUid,
    String stopUid,
    String reminderId,
    DateTime expiresAt,
  ) async {
    if (!_remindersReady) return;
    final raw = Map<String, dynamic>.from(
      (_reminders.get(routeUid) as Map?) ?? const {},
    );
    raw[stopUid] = {
      'id': reminderId,
      'exp': expiresAt.millisecondsSinceEpoch,
    };
    await _reminders.put(routeUid, raw);
  }

  static Future<void> removeReminder(String routeUid, String stopUid) async {
    if (!_remindersReady) return;
    final raw = Map<String, dynamic>.from(
      (_reminders.get(routeUid) as Map?) ?? const {},
    )..remove(stopUid);
    if (raw.isEmpty) {
      await _reminders.delete(routeUid);
    } else {
      await _reminders.put(routeUid, raw);
    }
  }
}
