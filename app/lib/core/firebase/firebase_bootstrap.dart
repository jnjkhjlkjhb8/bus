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

  static Future<void> initFailSoft({
    Future<void> Function() initializer = init,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      await initializer().timeout(timeout);
    } on Object catch (error, stack) {
      debugPrint('Firebase startup skipped: $error');
      debugPrintStack(stackTrace: stack);
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

  static Future<void> init() async {
    if (!FirebaseGate.enabled) return;
    FirebaseGate.ensureSecureTransport();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await runOptionalSteps([
      () => FirebaseAppCheck.instance.activate(
        providerApple: const AppleAppAttestProvider(),
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
            minimumFetchInterval: const Duration(hours: 1),
          ),
        );
        await remoteConfig.setDefaults(const {
          'maintenance_banner_enabled': false,
          'maintenance_banner_text': '',
          'push_enabled': true,
          'min_supported_version': '1.0.0',
          'arrival_lead_minutes': '1,3,5',
        });
        await remoteConfig.fetchAndActivate();
      },
      () async => updatePushPreference(requested: HiveStore.pushEnabled),
      () async {
        messaging.onTokenRefresh.listen(_syncToken);
      },
    ]);
  }

  static Future<bool> updatePushPreference({required bool requested}) async {
    HiveStore.pushEnabled = requested;
    if (!FirebaseGate.enabled) return requested;

    var enabled = false;
    if (requested) {
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
      if (token != null && token.isNotEmpty) await _syncToken(token);
    } on Object catch (_) {}
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
        },
      );
    } on Object catch (error, stack) {
      await FirebaseCrashlytics.instance.recordError(error, stack);
    }
  }
}
