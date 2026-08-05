import 'package:flutter/services.dart';

/// The platform → Dart direction of the tracking card's channel. Outbound
/// start/update/stop calls travel the same channel the other way and are
/// unaffected.
///
/// Two things arrive here:
///
/// - `onCancelTrack`, when the card's 取消追蹤 action is tapped. Every bloc that
///   can own a tracking session binds; only one session exists at a time, so
///   the ones without a live session ignore the call — cheaper and less fragile
///   than teaching the platform side which bloc is currently the owner.
/// - `onPushToken`, iOS only: each ActivityKit push token issued for the
///   current card, which the owner hands to the server so it can refresh that
///   card while the app is suspended (ADR-0018). Android's pushed refresh rides
///   the device's existing FCM token and needs nothing here.
///
/// One class for both because a MethodChannel has room for exactly one handler.
abstract final class AlightTrackInboundChannel {
  static const _channel = MethodChannel('com.wheres.bus/live_activity');

  static final _cancelListeners = <void Function()>[];
  static final _tokenListeners = <void Function(String token)>[];

  static void bind(void Function() onCancel) {
    _cancelListeners.add(onCancel);
    _install();
  }

  /// Binds a push-token listener. A stream of tokens rather than one: the
  /// system reissues them at its own discretion, and a card refreshed against a
  /// superseded token silently stops updating.
  static void bindPushToken(void Function(String token) onToken) {
    _tokenListeners.add(onToken);
    _install();
  }

  static void _install() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onCancelTrack':
          for (final listener in List.of(_cancelListeners)) {
            listener();
          }
        case 'onPushToken':
          final token = call.arguments as String?;
          if (token != null && token.isNotEmpty) {
            for (final listener in List.of(_tokenListeners)) {
              listener(token);
            }
          }
      }
      return null;
    });
  }

  /// Test seam: drops every binding so one test's listener cannot fire in the
  /// next.
  static void reset() {
    _cancelListeners.clear();
    _tokenListeners.clear();
  }
}
