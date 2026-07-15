import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:wheres_the_car/app/app.dart';
import 'package:wheres_the_car/core/bootstrap/app_bootstrap.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/firebase/firebase_bootstrap.dart';
import 'package:wheres_the_car/core/firebase/firebase_gate.dart';
import 'package:wheres_the_car/core/firebase/firebase_notifications.dart';
import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/core/storage/hive_store.dart';
import 'package:wheres_the_car/data/repositories/favorites_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (FirebaseGate.enabled) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // Start the maps renderer warmup first — it runs on the platform side and
  // overlaps with the Dart-side init below.
  _prewarmMapRenderer();

  // runApp must render the first frame immediately: Hive, Firebase, the
  // gRPC CA load, and PowerSync all do unbounded filesystem/network I/O, so
  // none of it may sit on this path (F11/F12). AppBootstrapController runs
  // it in the background and the UI listens to the resulting state instead
  // of `main` awaiting it.
  final bootstrap = AppBootstrapController(
    initHive: HiveStore.init,
    initGrpc: GrpcClient.init,
    initFirebase: FirebaseBootstrap.initFailSoft,
    initPowerSync: PowerSyncService.instance.init,
  );
  // Firebase core must exist before FirebaseBootstrap.initFailSoft's fuller
  // init runs (crash reporting, remote config, etc. all assume an app),
  // so it stays a background step ahead of `bootstrap.start()` rather than
  // sitting on the pre-runApp critical path with it.
  unawaited(
    FirebaseBootstrap.ensureCoreInitialized().catchError(CrashReporter.record),
  );
  unawaited(bootstrap.start());
  unawaited(
    FavoritesRepository.instance.migrateLegacy().catchError(
      CrashReporter.record,
    ),
  );

  runApp(App(bootstrap: bootstrap));
}

void _prewarmMapRenderer() {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  final maps = GoogleMapsFlutterPlatform.instance;
  if (maps is GoogleMapsFlutterAndroid) {
    unawaited(maps.warmup());
  }
}
