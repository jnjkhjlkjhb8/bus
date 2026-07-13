import 'package:flutter/services.dart';

class LiveActivityContent {
  const LiveActivityContent({
    required this.mode,
    required this.type,
    required this.routeOrTrain,
    required this.fromStation,
    required this.nextStation,
    this.previousStation,
    this.alightStation,
    this.remainingStops,
    this.progressPercent = 0.0,
    this.etaMs,
    this.walkMinutes = 0,
    this.plate,
    this.routeNumber,
  });

  final String mode;
  final String type;
  final String routeOrTrain;
  final String fromStation;
  final String nextStation;
  final String? previousStation;
  final String? alightStation;
  final int? remainingStops;
  final double progressPercent;
  final int? etaMs;
  final int walkMinutes;
  final String? plate;
  final String? routeNumber;

  Map<String, Object?> toArgs() => {
    'mode': mode,
    'type': type,
    'routeOrTrain': routeOrTrain,
    'fromStation': fromStation,
    'nextStation': nextStation,
    'previousStation': previousStation,
    'alightStation': alightStation,
    'remainingStops': remainingStops,
    'progressPercent': progressPercent,
    'etaMs': etaMs,
    // Legacy key: shipped Swift/Kotlin readers predate `etaMs`.
    'arrivalTimeMs': etaMs,
    'walkMinutes': walkMinutes,
    'plate': plate,
    'routeNumber': routeNumber,
  };
}

/// Thin wrapper over the platform live-activity channel. All platform errors
/// are swallowed: a broken lock-screen card must never break navigation.
class LiveActivityChannel {
  static const _channel = MethodChannel('com.wheres.bus/live_activity');
  bool _active = false;

  Future<void> start(LiveActivityContent content) async {
    try {
      await _channel.invokeMethod<String>('start', content.toArgs());
      _active = true;
    } on PlatformException {
      _active = false;
    } on MissingPluginException {
      _active = false;
    }
  }

  Future<void> update(LiveActivityContent content) async {
    if (!_active) return;
    try {
      await _channel.invokeMethod<void>('update', content.toArgs());
    } on PlatformException {
      // keep session alive; next update retries
    } on MissingPluginException {
      _active = false;
    }
  }

  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // already gone — nothing to clean up
    } on MissingPluginException {
      // no-op
    }
  }
}
