import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:wheres_the_car/core/firebase/firebase_telemetry.dart';
import 'package:wheres_the_car/firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  try {
    await FirebaseTelemetry.instance.notificationReceived(
      kind: FirebaseNotifications.kindFrom(message.data),
      foreground: false,
    );
  } on Object catch (_) {}
}

class FirebaseNotifications {
  FirebaseNotifications._();

  static String kindFrom(Map<String, dynamic> data) {
    final kind = data['kind']?.toString();
    return kind == null || kind.isEmpty ? 'unknown' : kind;
  }

  static Future<void> init() async {
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
    FirebaseMessaging.onMessage.listen(_received);
    FirebaseMessaging.onMessageOpenedApp.listen(_opened);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) await _opened(initial);
  }

  static Future<void> _received(RemoteMessage message) =>
      FirebaseTelemetry.instance.notificationReceived(
        kind: kindFrom(message.data),
        foreground: true,
      );

  static Future<void> _opened(RemoteMessage message) =>
      FirebaseTelemetry.instance.notificationOpened(
        kind: kindFrom(message.data),
      );
}
