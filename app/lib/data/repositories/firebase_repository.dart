import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:wheres_the_car/core/firebase/firebase_call_options.dart';
import 'package:wheres_the_car/core/firebase/firebase_gate.dart';
import 'package:wheres_the_car/core/firebase/install_identity.dart';
import 'package:wheres_the_car/core/grpc/grpc_client.dart';
import 'package:wheres_the_car/core/storage/hive_store.dart';
import 'package:wheres_the_car/data/generated/firebase.pbgrpc.dart';

bool isFirebaseRouteType(String value) => value == 'bus';

bool isArrivalReminderRouteType(String value) =>
    value == 'bus' || value == 'tra' || value == 'thsr';

class FirebaseRepository {
  FirebaseRepository({Firebase_ServiceClient? client}) : _client = client;

  static final instance = FirebaseRepository();

  Firebase_ServiceClient? _client;
  Firebase_ServiceClient get _grpc => _client ??= GrpcClient.instance.firebase;

  Future<DeviceState> upsertDevice({required String fcmToken}) async {
    if (!FirebaseGate.enabled) return DeviceState();
    final installId = await InstallIdentity.getOrCreate();
    return _grpc.upsertDevice(
      UpsertDeviceRequest(
        identity: DeviceIdentity(
          installId: installId,
          fcmToken: fcmToken,
          platform: defaultTargetPlatform.name,
          appVersion: const String.fromEnvironment(
            'APP_VERSION',
            defaultValue: '1.0.0',
          ),
        ),
        prefs: DevicePrefs(
          pushEnabled: HiveStore.pushEnabled,
          analyticsEnabled: HiveStore.analyticsEnabled,
          crashlyticsEnabled: HiveStore.crashlyticsEnabled,
          performanceEnabled: HiveStore.performanceEnabled,
        ),
      ),
      options: await FirebaseCallOptions.build(),
    );
  }

  Future<Ack> setRouteSubscription({
    required String routeType,
    required String routeKey,
    required bool enabled,
  }) async {
    if (!isFirebaseRouteType(routeType) || routeKey.isEmpty) {
      throw ArgumentError('invalid canonical route identity');
    }
    if (!FirebaseGate.enabled) return Ack(ok: true, message: 'disabled');
    return _grpc.setRouteSubscription(
      RouteSubscriptionRequest(
        installId: await InstallIdentity.getOrCreate(),
        routeType: routeType,
        routeKey: routeKey,
        enabled: enabled,
      ),
      options: await FirebaseCallOptions.build(),
    );
  }

  Future<ArrivalReminder> createArrivalReminder({
    required String routeType,
    required String routeKey,
    required String stopKey,
    required String direction,
    required int leadMinutes,
    required DateTime expiresAt,
  }) async {
    if (!isArrivalReminderRouteType(routeType) ||
        routeKey.isEmpty ||
        stopKey.isEmpty ||
        (direction != '0' && direction != '1')) {
      throw ArgumentError('invalid canonical arrival identity');
    }
    if (!FirebaseGate.enabled) {
      return ArrivalReminder(
        reminderId: 'local:$routeType:$routeKey:$stopKey:$leadMinutes',
      );
    }
    return _grpc.createArrivalReminder(
      CreateArrivalReminderRequest(
        installId: await InstallIdentity.getOrCreate(),
        routeType: routeType,
        routeKey: routeKey,
        stopKey: stopKey,
        direction: direction,
        leadMinutes: leadMinutes,
        expiresAtUnix: Int64(expiresAt.millisecondsSinceEpoch ~/ 1000),
      ),
      options: await FirebaseCallOptions.build(),
    );
  }

  Future<Ack> cancelArrivalReminder(String reminderId) async {
    if (!FirebaseGate.enabled) return Ack(ok: true, message: 'disabled');
    return _grpc.cancelArrivalReminder(
      CancelArrivalReminderRequest(
        reminderId: reminderId,
        installId: await InstallIdentity.getOrCreate(),
      ),
      options: await FirebaseCallOptions.build(),
    );
  }

  Future<DeviceState> listDeviceState() async {
    if (!FirebaseGate.enabled) return DeviceState();
    return _grpc.listDeviceState(
      DeviceRequest(installId: await InstallIdentity.getOrCreate()),
      options: await FirebaseCallOptions.build(),
    );
  }
}
