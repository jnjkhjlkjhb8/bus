import 'dart:async';
import 'dart:io' show Platform;

import 'package:hive_ce_flutter/adapters.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wheres_the_bus/core/http/static_version.dart';

class HiveStore {
  HiveStore._();

  static const _boxLayout = 'board_layout';
  static const _boxFavRoutes = 'fav_routes';
  static const _boxFavorites = 'favorites';
  static const _boxSettings = 'settings';
  static const _boxRecents = 'recent_searches';
  static const _boxReminders = 'arrival_reminders';
  static const _boxSavedPlans = 'saved_plans';
  static const _boxStaticCache = 'static_cache';

  /// Key holding the build number the cached entries were written by. A
  /// mismatch truncates the whole box — see [pruneStaticCache].
  static const _cacheEpochKey = '__epoch';

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
    // Only the boxes the splash path actually reads block startup. The
    // rest (saved plans, reminders, board layout, recent queries) are opened
    // lazily below so they stop contending for I/O during app launch —
    // `recent_searches` alone measured ~410 ms of the ~470 ms splash, and its
    // only reader is the rail query sheet.
    await Future.wait([
      Hive.openBox<dynamic>(_boxFavRoutes),
      Hive.openBox<dynamic>(_boxFavorites),
      Hive.openBox<dynamic>(_boxSettings),
    ]);
    unawaited(_openLazyBoxes());
  }

  static Future<void>? _lazyFuture;

  /// Opens the non-critical boxes. Kicked off unawaited right after the
  /// critical boxes finish (see [_open]); callers that need one of these
  /// boxes before it's open should check the matching `*Ready` getter, same
  /// as the existing pattern for [favoritesReady]/[settingsReady].
  static Future<void> _openLazyBoxes() {
    return _lazyFuture ??=
        Future.wait([
          Hive.openBox<dynamic>(_boxLayout),
          Hive.openBox<dynamic>(_boxReminders),
          Hive.openBox<dynamic>(_boxSavedPlans),
          Hive.openBox<dynamic>(_boxRecents),
          Hive.openBox<dynamic>(_boxStaticCache),
        ]).then((_) => pruneStaticCache()).catchError((Object _) {
          // Unawaited by design: a lazy box that fails to open must not crash
          // the zone. Clearing the memo lets a later init() retry re-attempt;
          // until then the `*Ready` guards keep the affected features off.
          _lazyFuture = null;
        });
  }

  /// Drops offline-cache entries that can no longer be trusted (ADR-0017).
  ///
  /// Two independent rules, cheapest first:
  ///
  /// * The cache epoch is the running build number paired with the backend's
  ///   static dataset version. Entries hold verbatim protobuf bytes (plus the
  ///   write timestamp [getStaticFresh] reads), and a proto change ships app
  ///   and backend together, so every wire-breaking change also changes the
  ///   build number — a mismatch means the whole box may decode to garbage and
  ///   is truncated. The version half is what makes a cache-first entry
  ///   (`routeStatic`) notice an upstream edit: it moves only when the nightly
  ///   load republishes the static tables, so a rebuilt dataset expires the
  ///   box on the next launch instead of the entry waiting out its `maxAge`.
  ///   A version that cannot be fetched keeps the stored one — see
  ///   [fetchStaticVersion].
  /// * `d:<yyyy-MM-dd>:` entries are service-date scoped. Past dates are
  ///   deleted; today and future dates are kept, because the rail query sheet
  ///   can legitimately look up a timetable days ahead and that entry must
  ///   survive the launches between caching it and travelling.
  ///
  /// [now], [buildNumber] and [staticVersion] are injectable for tests only.
  static Future<void> pruneStaticCache({
    DateTime? now,
    Future<String> Function()? buildNumber,
    Future<String?> Function()? staticVersion,
  }) async {
    if (!staticCacheReady) return;
    final box = staticCache;
    final build = await (buildNumber ?? _currentBuildNumber)();
    final stored = box.get(_cacheEpochKey);
    final version =
        await (staticVersion ?? fetchStaticVersion)() ?? _versionOf(stored);
    final epoch = '$build|$version';
    if (stored != epoch) {
      await box.clear();
      await box.put(_cacheEpochKey, epoch);
      return;
    }
    final today = dateStamp(now ?? DateTime.now());
    // linear key scan. The box holds one entry per route/OD the rider has
    // opened — hundreds at most. Split by prefix into its own box if that
    // ever reaches thousands.
    final stale = box.keys
        .whereType<String>()
        .where((k) => _isPastDateKey(k, today))
        .toList();
    if (stale.isNotEmpty) await box.deleteAll(stale);
  }

  /// The dataset-version half of a stored epoch, used as the fallback when the
  /// backend cannot be reached. An epoch written before this pairing existed
  /// has no separator and yields '', which reads as "unknown" and truncates
  /// once — the same launch already changes the build half anyway.
  static String _versionOf(Object? epoch) {
    if (epoch is! String) return '';
    final separator = epoch.indexOf('|');
    return separator < 0 ? '' : epoch.substring(separator + 1);
  }

  static bool _isPastDateKey(String key, String today) {
    if (!key.startsWith('d:')) return false;
    final end = key.indexOf(':', 2);
    if (end < 0) return false;
    return key.substring(2, end).compareTo(today) < 0;
  }

  static Future<String> _currentBuildNumber() =>
      PackageInfo.fromPlatform().then((i) => i.buildNumber);

  /// Service-date stamp used by `d:` cache keys, matching the `yyyy-MM-dd`
  /// the rail screens already send to the router. Zero-padded so keys sort
  /// and compare lexicographically.
  static String dateStamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static bool get staticCacheReady => Hive.isBoxOpen(_boxStaticCache);
  static Box<dynamic> get staticCache => Hive.box(_boxStaticCache);

  /// Verbatim protobuf response bytes for [key], or null on a miss.
  ///
  /// [HiveStore] deliberately never decodes these: keeping the box opaque is
  /// what lets generated proto types stay inside `app/lib/data/` as the
  /// CONTEXT.md operating rule requires. Callers serialize and decode in
  /// their repository.
  static List<int>? getStatic(String key) =>
      staticCacheReady ? _bytesOf(staticCache.get(key)) : null;

  /// Same as [getStatic], but only when the entry was written less than
  /// [maxAge] ago — the read a cache-first caller makes before touching the
  /// network. An entry written by a build that predates the timestamp, or one
  /// stamped in the future because the device clock moved backwards, counts as
  /// expired: the safe direction is to refetch.
  static List<int>? getStaticFresh(String key, Duration maxAge) {
    if (!staticCacheReady) return null;
    final value = staticCache.get(key);
    if (value is! Map) return null;
    final writtenAt = value['t'];
    if (writtenAt is! int) return null;
    final age = DateTime.now().millisecondsSinceEpoch - writtenAt;
    if (age < 0 || age > maxAge.inMilliseconds) return null;
    return _bytesOf(value);
  }

  static List<int>? _bytesOf(Object? value) {
    final bytes = value is Map ? value['b'] : value;
    return bytes is List ? bytes.cast<int>() : null;
  }

  static Future<void> putStatic(String key, List<int> bytes) {
    if (!staticCacheReady) return Future<void>.value();
    return staticCache.put(key, {
      'b': bytes,
      't': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<void> deleteStatic(String key) {
    if (!staticCacheReady) return Future<void>.value();
    return staticCache.delete(key);
  }

  static bool get layoutReady => Hive.isBoxOpen(_boxLayout);
  static Box<dynamic> get layout => Hive.box(_boxLayout);
  static Box<dynamic> get favRoutes => Hive.box(_boxFavRoutes);
  static bool get recentsReady => Hive.isBoxOpen(_boxRecents);
  static Box<dynamic> get recents => Hive.box(_boxRecents);

  /// Empty until the lazily-opened box is ready (see [recentsReady]).
  static List<Map<String, dynamic>> get recentSearches {
    if (!recentsReady) return const [];
    return (recents.get('items', defaultValue: const <dynamic>[]) as List)
        .cast<Map<dynamic, dynamic>>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }

  static Future<void> addRecentSearch(Map<String, dynamic> item) async {
    if (!recentsReady) return;
    final items = recentSearches
      ..removeWhere(
        (e) => e['uid'] == item['uid'] && e['type'] == item['type'],
      )
      ..insert(0, item);
    await recents.put('items', items.take(10).toList());
  }

  /// Recent rail train-number queries as `{system, trainNo}`, newest first.
  /// Empty until the lazily-opened box is ready (see [recentsReady]).
  static List<Map<String, dynamic>> get recentTrainQueries {
    if (!recentsReady) return const [];
    return (recents.get('train_queries', defaultValue: const <dynamic>[])
            as List)
        .cast<Map<dynamic, dynamic>>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }

  static Future<void> addRecentTrainQuery(
    String system,
    String trainNo,
  ) async {
    if (!recentsReady) return;
    final items = recentTrainQueries
      ..removeWhere(
        (e) => e['system'] == system && e['trainNo'] == trainNo,
      )
      ..insert(0, {'system': system, 'trainNo': trainNo});
    await recents.put('train_queries', items.take(6).toList());
  }

  /// Recent rail origin/destination pairs as
  /// `{system, originId, originName, destId, destName}`, newest first.
  ///
  /// User intent, not cache: this survives an app update, which is why it
  /// lives here and not in the `static_cache` box that every release
  /// truncates. Stored as a capped list even though only the newest entry per
  /// system is read today, so a recent-pairs list can be added later without
  /// migrating what riders already have.
  static List<Map<String, dynamic>> get recentOdQueries {
    if (!recentsReady) return const [];
    return (recents.get('od_queries', defaultValue: const <dynamic>[]) as List)
        .cast<Map<dynamic, dynamic>>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }

  /// The newest origin/destination pair for [system], or null if the rider
  /// has never queried that system. Scoped per system because TRA and THSR
  /// station names do not overlap — a global "last pair" would prefill the
  /// THSR screen with TRA stations.
  static Map<String, dynamic>? lastOdQuery(String system) {
    for (final entry in recentOdQueries) {
      if (entry['system'] == system) return entry;
    }
    return null;
  }

  static Future<void> addRecentOdQuery({
    required String system,
    required String originId,
    required String originName,
    required String destId,
    required String destName,
  }) async {
    if (!recentsReady) return;
    final items = recentOdQueries
      ..removeWhere(
        (e) =>
            e['system'] == system &&
            e['originName'] == originName &&
            e['destName'] == destName,
      )
      ..insert(0, {
        'system': system,
        'originId': originId,
        'originName': originName,
        'destId': destId,
        'destName': destName,
      });
    await recents.put('od_queries', items.take(6).toList());
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

  /// Last position the OS actually reported for this device, as `[lat, lon]`.
  ///
  /// Seeds home's camera and its *first* nearby query on the next launch, so
  /// neither waits on `getLastKnownPosition` — which costs ~700 ms cold, and
  /// returns nothing at all on a device whose OS cache has been evicted, where
  /// the fallback is a GPS fix several seconds out. Null before the first fix.
  static List<double>? get lastDevicePosition {
    if (!settingsReady) return null;
    final raw = settings.get('last_device_position');
    if (raw is! List || raw.length != 2) return null;
    final [lat, lon] = raw;
    if (lat is! num || lon is! num) return null;
    return [lat.toDouble(), lon.toDouble()];
  }

  static Future<void> setLastDevicePosition(double lat, double lon) async {
    if (!settingsReady) return;
    await settings.put('last_device_position', [lat, lon]);
  }

  /// Mirrors `SettingsRepository.liveActivityEnabled`: Android is force-
  /// disabled while the Live Update surface is paused.
  static bool get liveActivityEnabled =>
      !Platform.isAndroid &&
      settings.get('live_activity_enabled', defaultValue: true) as bool;

  static set liveActivityEnabled(bool v) =>
      settings.put('live_activity_enabled', v);

  /// The `latest_version` the rider last waved off, so the update nudge stays
  /// silent across launches for that release only. Null before any dismissal.
  ///
  /// Guarded on [settingsReady] like every other read here: the gate's first
  /// check can land before Hive's lazy boxes open, and an unopened box throws.
  /// Null then just means "not dismissed", which nudges — the safe direction.
  static String? get dismissedUpdateVersion {
    if (!settingsReady) return null;
    final raw = settings.get('dismissed_update_version');
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  static Future<void> setDismissedUpdateVersion(String v) async {
    if (!settingsReady) return;
    await settings.put('dismissed_update_version', v);
  }

  // Defaults to false-until-asked: a brand-new install has no stored value,
  // and `FirebaseBootstrap.init` passes this straight through as the
  // `requested` permission on first launch (F-push-launch). Defaulting it
  // true used to fire the OS permission dialog on first launch with no
  // context. An existing user who already granted push always has an
  // explicit `true` persisted here (every `updatePushPreference` call
  // writes the real, OS-reconciled value before returning — see
  // `FirebaseBootstrap.updatePushPreference`), so this default only ever
  // applies to installs that have never been through that flow.
  static bool get pushEnabled =>
      settings.get('push_enabled', defaultValue: false) as bool;

  static set pushEnabled(bool value) => settings.put('push_enabled', value);

  /// The 北部/南部 half the rider last picked from in the TRA station picker,
  /// so it reopens where they left off. Guarded like the other settings reads:
  /// null means "no preference", and the picker falls back to its default.
  static String? get traHemisphere {
    if (!settingsReady) return null;
    final raw = settings.get('tra_hemisphere');
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  static Future<void> setTraHemisphere(String v) async {
    if (!settingsReady) return;
    await settings.put('tra_hemisphere', v);
  }

  static List<String> get favMetroStations => List<String>.from(
    settings.get('fav_metro_stations', defaultValue: <String>[]) as List,
  );

  static set favMetroStations(List<String> list) =>
      settings.put('fav_metro_stations', list);

  // Active metro alight-reminder session (ADR-0015). Persisted in the settings
  // box (opened on the critical path) so the bell state, Live Activity, and
  // re-watch survive an app restart. Only one session is active at a time.
  static const _mrtTrackKey = 'mrt_track_session';
  static const _alightFiredKey = 'mrt_track_fired_id';

  static Map<String, dynamic>? get mrtTrackSession {
    final raw = settings.get(_mrtTrackKey) as Map?;
    return raw?.cast<String, dynamic>();
  }

  static Future<void> putMrtTrackSession(Map<String, dynamic> json) =>
      settings.put(_mrtTrackKey, json);

  static Future<void> clearMrtTrackSession() => settings.delete(_mrtTrackKey);

  /// Whether a 下車提醒 vibration has already gone off for [firedKey]
  /// (`sessionId:event`) — guards against a double buzz when the live stream
  /// and the FCM data message both deliver the same crossing. One slot is
  /// enough: a session's two events can only be crossed in order, and a new
  /// session carries a different id. The Hive key keeps its ADR-0015 name so
  /// an upgrade doesn't re-fire a session in flight.
  static bool isAlightFired(String firedKey) =>
      firedKey.isNotEmpty && settings.get(_alightFiredKey) == firedKey;

  static Future<void> markAlightFired(String firedKey) =>
      settings.put(_alightFiredKey, firedKey);

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
