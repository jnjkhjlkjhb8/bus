import 'dart:async';

import 'package:wheres_the_bus/core/haptics/haptic_service.dart';
import 'package:wheres_the_bus/core/storage/hive_store.dart';

/// The two moments a 下車提醒 speaks up. One vocabulary for bus, 雙鐵 and
/// 捷運 (ADR-0020) — the rider learns two feelings once, not six.
enum AlightEvent {
  /// The 提前提醒站 is the next stop. Only exists above 提前站數 0.
  lead,

  /// The 下車站 is the next stop.
  alight,
}

/// Fires the vibration for [event] on session [sessionId], at most once.
///
/// Both delivery paths land here — the live stream while the app is in front,
/// and the FCM data message when it is not — so the Hive fired-guard is what
/// stops a double buzz when both deliver the same crossing (the guard metro
/// already relied on, generalised to two events per session).
Future<void> fireAlightHaptics(
  String sessionId,
  AlightEvent event, {
  HapticService? haptics,
}) async {
  if (sessionId.isEmpty) return;
  final key = '$sessionId:${event.name}';
  if (HiveStore.settingsReady && HiveStore.isAlightFired(key)) return;
  if (HiveStore.settingsReady) await HiveStore.markAlightFired(key);
  final h = haptics ?? HapticService.instance;
  switch (event) {
    case AlightEvent.lead:
      await h.shortAlightPulse();
    case AlightEvent.alight:
      // Fire-and-forget: the long buzz runs on its own timer for 1.6 s and
      // nothing downstream waits on it finishing.
      h.longAlightPulse();
  }
}

/// Which vibration a stops-remaining change earns, or null for none.
///
/// [remaining] counts stops to the 下車站, where 1 means "your stop is next".
/// The lead event sits at `lead + 1` because the 提前提醒站 is [lead] stops
/// before the target, so it being *next* leaves `lead + 1` to go. At lead 0
/// the two collapse onto the same crossing and only the long buzz survives —
/// which is what "不提前提醒" means: no early warning, never a silent stop.
///
/// Only a genuine crossing counts. A feed that re-reports the same position,
/// or flaps backwards and forwards across the threshold, must not re-fire.
AlightEvent? alightEventFor({
  required int? previousRemaining,
  required int remaining,
  required int lead,
}) {
  if (previousRemaining == null || previousRemaining <= remaining) return null;
  if (remaining == 1) return AlightEvent.alight;
  if (lead > 0 && remaining == lead + 1) return AlightEvent.lead;
  return null;
}
