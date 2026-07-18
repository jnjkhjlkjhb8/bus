import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:wheres_the_car/core/firebase/firebase_gate.dart';
import 'package:wheres_the_car/core/firebase/firebase_notifications.dart';
import 'package:wheres_the_car/core/firebase/firebase_telemetry.dart';
import 'package:wheres_the_car/core/firebase/remote_config.dart';
import 'package:wheres_the_car/core/storage/hive_store.dart';
import 'package:wheres_the_car/data/repositories/firebase_repository.dart';
import 'package:wheres_the_car/firebase_options.dart';

class FirebaseTokenSyncGuard {
  String? _lastKey;
  String? _inFlightKey;
  Future<void>? _inFlight;

  Future<void> run(
    String token,
    String prefsKey,
    Future<void> Function() sync,
  ) async {
    final key = '$token\u0000$prefsKey';
    if (key == _lastKey) return;
    if (key == _inFlightKey) return _inFlight;
    if (_inFlight != null) {
      try {
        await _inFlight;
      } on Object catch (_) {}
      return run(token, prefsKey, sync);
    }

    _inFlightKey = key;
    final future = Future<void>.sync(sync);
    _inFlight = future;
    try {
      await future;
      _lastKey = key;
    } finally {
      if (identical(_inFlight, future)) {
        _inFlight = null;
        _inFlightKey = null;
      }
    }
  }
}

class FirebaseBootstrap {
  FirebaseBootstrap._();

  static final _tokenSyncGuard = FirebaseTokenSyncGuard();
  static bool _notificationsInitialized = false;
  static StreamSubscription<RemoteConfigUpdate>? _remoteConfigSub;
  static StreamSubscription<String>? _tokenRefreshSub;
  static Future<void>? _coreInitFuture;

  /// Runs [init] (or [initializer] in tests) as the app's single best-effort
  /// Firebase step, bounded by [timeout].
  ///
  /// this used to catch and log every failure and return normally,
  /// so `AppBootstrapController` — which relies on this throwing to know
  /// the step failed — always saw success and never degraded the app even
  /// when Firebase never came up. It now rethrows after logging, so a real
  /// failure reaches the controller and lands the app in `degraded`.
  static Future<void> initFailSoft({
    Future<void> Function({Future<void>? hiveReady}) initializer = init,
    Duration timeout = const Duration(seconds: 10),
    Future<void>? hiveReady,
  }) async {
    try {
      await initializer(hiveReady: hiveReady).timeout(timeout);
    } on Object catch (error, stack) {
      debugPrint('Firebase startup skipped: $error');
      debugPrintStack(stackTrace: stack);
      rethrow;
    }
  }

  static Future<void> runOptionalSteps(
    Iterable<Future<void> Function()> steps,
  ) async {
    for (final step in steps) {
      try {
        await step();
      } on Object catch (error, stack) {
        debugPrint('Firebase optional setup skipped: $error');
        debugPrintStack(stackTrace: stack);
      }
    }
  }

  /// Single-flight guard: concurrent callers share one in-flight
  /// [Firebase.initializeApp] instead of each racing their own call (P1-09
  /// — `main.dart` fires this off the same background tick as
  /// `AppBootstrapController.start`, which also reaches Firebase init via
  /// [initFailSoft]/[init]). A failure is not permanently cached, matching
  /// `HiveStore.init`'s convention: the next call retries from scratch.
  ///
  /// Exposed with an injectable [initializer] so the memoization behavior
  /// itself is unit-testable — [FirebaseGate.enabled] is compile-time
  /// `false` under `flutter test`, which would otherwise make every call
  /// through [ensureCoreInitialized] a no-op regardless of concurrency.
  @visibleForTesting
  static Future<void> singleFlightCoreInit(
    Future<void> Function() initializer,
  ) {
    final existing = _coreInitFuture;
    if (existing != null) return existing;
    final future = initializer();
    _coreInitFuture = future;
    unawaited(
      future.catchError((Object _, StackTrace _) {
        _coreInitFuture = null;
      }),
    );
    return future;
  }

  @visibleForTesting
  static void resetCoreInitForTesting() => _coreInitFuture = null;

  static Future<void> ensureCoreInitialized() {
    if (!FirebaseGate.enabled || Firebase.apps.isNotEmpty) {
      return Future<void>.value();
    }
    return singleFlightCoreInit(() async {
      FirebaseGate.ensureSecureTransport();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    });
  }

  static Future<void> init({Future<void>? hiveReady}) async {
    if (!FirebaseGate.enabled) return;
    await ensureCoreInitialized();
    // Everything below this point (App Check, analytics/crashlytics
    // collection toggles, remote config, push preference) either reads a
    // HiveStore preference directly or transitively depends on one, so it
    // all waits for Hive's boxes to be open (P1-09: reading an unopened box
    // throws) rather than each step re-deriving its own guard. `main.dart`
    // injects the exact `HiveStore.init()` future it started Hive with.
    await hiveReady;
    const isProd = FirebaseGate.appEnv == 'production';
    await runOptionalSteps([
      () => FirebaseAppCheck.instance.activate(
        providerApple: isProd
            ? const AppleAppAttestProvider()
            : const AppleDebugProvider(),
        providerAndroid: isProd
            ? const AndroidPlayIntegrityProvider()
            : const AndroidDebugProvider(),
      ),
    ]);
    FlutterError.onError = (details) {
      unawaited(FirebaseCrashlytics.instance.recordFlutterFatalError(details));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: true)
          .ignore();
      return true;
    };

    final remoteConfig = FirebaseRemoteConfig.instance;
    final messaging = FirebaseMessaging.instance;
    await runOptionalSteps([
      () => FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
        HiveStore.analyticsEnabled,
      ),
      () => FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        HiveStore.crashlyticsEnabled,
      ),
      () => FirebasePerformance.instance.setPerformanceCollectionEnabled(
        HiveStore.performanceEnabled,
      ),
      () async {
        await remoteConfig.setConfigSettings(
          RemoteConfigSettings(
            fetchTimeout: const Duration(seconds: 5),
            // Short so a cold start reflects an ops push (maintenance banner,
            // min version) quickly; foreground apps use Realtime below.
            minimumFetchInterval: const Duration(minutes: 1),
          ),
        );
        await remoteConfig.setDefaults(AppConfig.defaults);
        await remoteConfig.fetchAndActivate();
        // This init runs after runApp (fire-and-forget), so the UI already
        // built with defaults — bump to re-read the just-fetched values.
        AppConfig.version.value++;
        // Realtime updates: apply an ops push to foreground apps within
        // seconds, bypassing minimumFetchInterval. iOS/Android only.
        // Own the subscription (F59): cancel any prior one first so a
        // repeated init (hot restart, retried bootstrap) never stacks a
        // second listener applying the same update twice.
        await _remoteConfigSub?.cancel();
        _remoteConfigSub = remoteConfig.onConfigUpdated.listen((_) async {
          await remoteConfig.activate();
          AppConfig.version.value++;
        });
      },
      // `HiveStore.pushEnabled` defaults to false until a user has actually
      // gone through the permission flow (settings toggle or a prior grant),
      // so this only re-requests the OS permission (and re-syncs the FCM
      // token) for users who already have push on. It never surfaces the OS
      // dialog on a fresh install, because `requested` is false there.
      () async => updatePushPreference(requested: HiveStore.pushEnabled),
      () async {
        await _tokenRefreshSub?.cancel();
        _tokenRefreshSub = messaging.onTokenRefresh.listen(_syncToken);
      },
    ]);
  }

  /// Cancels the owned Remote Config / token-refresh subscriptions. Exposed
  /// for tests; production code has no teardown path today since Firebase
  /// lives for the app's lifetime, but this keeps `init()` idempotent under
  /// re-entry (retry, hot restart) without leaking listeners (F59).
  @visibleForTesting
  static Future<void> disposeForTesting() async {
    await _remoteConfigSub?.cancel();
    _remoteConfigSub = null;
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
  }

  static Future<bool> updatePushPreference({required bool requested}) async {
    HiveStore.pushEnabled = requested;
    debugPrint(
      '[firebase-reg] enabled=${FirebaseGate.enabled} '
      'requested=$requested',
    );
    if (!FirebaseGate.enabled) return requested;

    var enabled = false;
    // Remote kill switch: ops can disable push app-wide without a release.
    if (requested && AppConfig.getBool('push_enabled')) {
      try {
        final permission = await FirebaseMessaging.instance.requestPermission();
        enabled =
            permission.authorizationStatus == AuthorizationStatus.authorized ||
            permission.authorizationStatus == AuthorizationStatus.provisional;
      } on Object catch (_) {}
    }
    HiveStore.pushEnabled = enabled;
    if (enabled && !_notificationsInitialized) {
      try {
        await FirebaseNotifications.init();
        _notificationsInitialized = true;
      } on Object catch (_) {}
    }
    try {
      await FirebaseTelemetry.instance.notificationPermissionChanged(
        enabled: enabled,
      );
    } on Object catch (_) {}
    try {
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint(
        '[firebase-reg] fcm token '
        '${token == null ? 'null' : 'len=${token.length}'}',
      );
      if (token != null && token.isNotEmpty) await _syncToken(token);
    } on Object catch (error) {
      debugPrint('[firebase-reg] getToken failed: $error');
    }
    return enabled;
  }

  static Future<void> _syncToken(String token) async {
    try {
      await _tokenSyncGuard.run(
        token,
        '${HiveStore.pushEnabled}:${HiveStore.analyticsEnabled}:'
        '${HiveStore.crashlyticsEnabled}:'
        '${HiveStore.performanceEnabled}',
        () async {
          await FirebaseRepository.instance.upsertDevice(fcmToken: token);
          debugPrint('[firebase-reg] upsertDevice ok');
        },
      );
    } on Object catch (error, stack) {
      debugPrint('[firebase-reg] upsertDevice failed: $error');
      await FirebaseCrashlytics.instance.recordError(error, stack);
    }
  }
}
