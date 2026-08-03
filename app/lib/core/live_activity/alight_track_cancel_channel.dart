import 'package:flutter/services.dart';

/// Receives the tracking card's 取消追蹤 action. The native plugin fires
/// `onCancelTrack` on the shared channel when the notification action is
/// tapped; outbound start/update/stop calls travel the same channel in the
/// opposite direction and are unaffected.
///
/// Every bloc that can own a tracking session binds here. Only one session
/// exists at a time, so the ones without a live session ignore the call —
/// cheaper and less fragile than teaching the platform side which bloc is
/// currently the owner.
abstract final class AlightTrackCancelChannel {
  static const _channel = MethodChannel('com.wheres.bus/live_activity');

  static final _listeners = <void Function()>[];

  static void bind(void Function() onCancel) {
    _listeners.add(onCancel);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onCancelTrack') {
        for (final listener in List.of(_listeners)) {
          listener();
        }
      }
      return null;
    });
  }

  /// Test seam: drops every binding so one test's listener cannot fire in the
  /// next.
  static void reset() => _listeners.clear();
}
