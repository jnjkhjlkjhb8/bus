import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:wheres_the_car/app/app.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/firebase/firebase_bootstrap.dart';
import 'package:wheres_the_car/core/firebase/firebase_gate.dart';
import 'package:wheres_the_car/core/firebase/firebase_notifications.dart';
import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/core/storage/hive_store.dart';
import 'package:wheres_the_car/data/repositories/favorites_repository.dart';

Future<void> main() async {
  await _bootstrap();
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (FirebaseGate.enabled) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // Start the maps renderer warmup first — it runs on the platform side and
  // overlaps with the Dart-side init below.
  _prewarmMapRenderer();

  // Hive, Firebase core, and the gRPC CA load have no ordering dependencies;
  // running them in parallel keeps the native splash to the slowest of the
  // three instead of their sum.
  final sw = Stopwatch()..start();
  await Future.wait([
    HiveStore.init()
        .then<void>((_) {
          if (!kReleaseMode) {
            debugPrint('[boot] HiveStore.init ${sw.elapsedMilliseconds}ms');
          }
        })
        .catchError(CrashReporter.record)
        .whenComplete(() => App.isInitialized.value = true),
    FirebaseBootstrap.ensureCoreInitialized().catchError(CrashReporter.record),
    GrpcClient.init().catchError(CrashReporter.record),
  ]);
  if (!kReleaseMode) {
    debugPrint('[boot] pre-runApp init ${sw.elapsedMilliseconds}ms');
  }
  _initializeRemoteServices();
  unawaited(
    FavoritesRepository.instance.migrateLegacy().catchError(
      CrashReporter.record,
    ),
  );

  runApp(const App());
}

void _prewarmMapRenderer() {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  final maps = GoogleMapsFlutterPlatform.instance;
  if (maps is GoogleMapsFlutterAndroid) {
    unawaited(maps.warmup());
  }
}

void _initializeRemoteServices() {
  Future.wait([
    PowerSyncService.instance.init().catchError((Object e, StackTrace s) {
      CrashReporter.record(e, s);
    }),
    FirebaseBootstrap.initFailSoft(),
  ]).ignore();
}
