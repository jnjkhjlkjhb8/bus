import 'package:wheres_the_car/data/generated/firebase.pb.dart';
import 'package:wheres_the_car/data/models/firebase_models.dart';

class FirebaseDecoder {
  const FirebaseDecoder._();
  static const FirebaseDecoder instance = FirebaseDecoder._();

  FirebaseAck decodeAck(Ack a) => FirebaseAck(ok: a.ok, message: a.message);

  FirebaseDeviceState decodeDeviceState(DeviceState s) => FirebaseDeviceState(
    installId: s.identity.installId,
    fcmToken: s.identity.fcmToken,
    platform: s.identity.platform,
    appVersion: s.identity.appVersion,
    pushEnabled: s.prefs.pushEnabled,
    analyticsEnabled: s.prefs.analyticsEnabled,
    crashlyticsEnabled: s.prefs.crashlyticsEnabled,
    performanceEnabled: s.prefs.performanceEnabled,
  );

  ArrivalReminderReceipt decodeReminder(ArrivalReminder r) =>
      ArrivalReminderReceipt(reminderId: r.reminderId);
}
