import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:wheres_the_bus/core/firebase/firebase_telemetry.dart';
import 'package:wheres_the_bus/features/metro/data/mrt_track_vibration.dart';
import 'package:wheres_the_bus/firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  // The 捷運下車提醒 lead alert is a data-only message: vibrate with no banner,
  // nothing in the notification center (ADR-0015). Background delivery lands
  // here rather than on onMessage.
  await FirebaseNotifications.maybeVibrateForMrt(message.data);
  try {
    await FirebaseTelemetry.instance.notificationReceived(
      kind: FirebaseNotifications.kindFrom(message.data),
      foreground: false,
    );
  } on Object catch (_) {}
}

class FirebaseNotifications {
  FirebaseNotifications._();

  /// Data-message type for the metro alight lead vibration (ADR-0015).
  static const _mrtVibrateType = 'mrt_vibrate';

  static String kindFrom(Map<String, dynamic> data) {
    final kind = data['kind']?.toString();
    return kind == null || kind.isEmpty ? 'unknown' : kind;
  }

  /// Fires the alight vibration when [data] is a `mrt_vibrate` message,
  /// guarded so it never double-buzzes against the WatchTrack stream path.
  static Future<void> maybeVibrateForMrt(Map<String, dynamic> data) async {
    if (data['type']?.toString() != _mrtVibrateType) return;
    final trackId = data['track_id']?.toString() ?? '';
    try {
      await fireMrtLeadVibration(trackId);
    } on Object catch (_) {}
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

  static Future<void> _received(RemoteMessage message) async {
    await maybeVibrateForMrt(message.data);
    await FirebaseTelemetry.instance.notificationReceived(
      kind: kindFrom(message.data),
      foreground: true,
    );
  }

  static Future<void> _opened(RemoteMessage message) =>
      FirebaseTelemetry.instance.notificationOpened(
        kind: kindFrom(message.data),
      );
}
