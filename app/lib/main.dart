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

  final sw = Stopwatch()..start();
  try {
    await HiveStore.init();
    if (!kReleaseMode) {
      debugPrint('[boot] HiveStore.init ${sw.elapsedMilliseconds}ms');
    }
  } on Object catch (e, s) {
    CrashReporter.record(e, s);
  } finally {
    App.isInitialized.value = true;
  }

  _prewarmMapRenderer();
  await GrpcClient.init();
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
