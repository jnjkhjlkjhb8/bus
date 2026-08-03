import 'package:flutter/widgets.dart';

/// Whether the app is on screen. Live gRPC feeds gate on this
/// (`ResilientSubscription`) so a backgrounded app holds no stream open: an app
/// the user cannot see has nothing to keep fresh, and the radio wakeups a live
/// ETA stream causes every few seconds are pure battery cost there.
///
/// `inactive` counts as foreground. It is the transient state of an
/// app-switcher swipe, a notification-shade pull, or an incoming call, and
/// dropping every stream for it would mean a reconnect storm on gestures the
/// user reads as "still in the app".
///
/// Journey tracking is deliberately *not* gated on this: its ETA streams are
/// subscribed directly (not through `ResilientSubscription`) because the
/// Android Live Activity notification must keep counting down while the app
/// sits in the background.
class AppForeground {
  AppForeground._();

  static final ValueNotifier<bool> value = ValueNotifier<bool>(true);

  static AppLifecycleListener? _listener;

  /// Starts observing the lifecycle. Idempotent; called once from `App`.
  static void start() {
    _listener ??= AppLifecycleListener(
      onStateChange: (state) => value.value = switch (state) {
        AppLifecycleState.resumed || AppLifecycleState.inactive => true,
        AppLifecycleState.hidden ||
        AppLifecycleState.paused ||
        AppLifecycleState.detached => false,
      },
    );
  }

  @visibleForTesting
  static void reset() {
    _listener?.dispose();
    _listener = null;
    value.value = true;
  }
}
