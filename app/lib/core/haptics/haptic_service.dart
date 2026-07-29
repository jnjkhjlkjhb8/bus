import 'dart:async';
import 'package:flutter/services.dart';

/// Centralised haptic feedback — including the 6.7-second sustained bus
/// arrival vibration.
class HapticService {
  HapticService._();
  static final HapticService instance = HapticService._();

  Timer? _sustainedTimer;

  Future<void> lightTap() => HapticFeedback.lightImpact();
  Future<void> mediumTap() => HapticFeedback.mediumImpact();
  Future<void> heavyTap() => HapticFeedback.heavyImpact();
  Future<void> selectionClick() => HapticFeedback.selectionClick();

  /// Strong double pulse for the 捷運下車提醒 lead alert (ADR-0015): two heavy
  /// impacts a beat apart, felt not read. Reuses the platform haptics channel
  /// rather than a bespoke VibrationEffect plugin.
  Future<void> doubleStrongPulse() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 160));
    await HapticFeedback.heavyImpact();
  }

  /// 6.7-second pulse for bus arrival reminder.
  /// Repeats heavy impact every 200ms for the duration.
  void startArrivalVibration() {
    _sustainedTimer?.cancel();
    const pulseInterval = Duration(milliseconds: 200);
    final endTime = DateTime.now().add(const Duration(milliseconds: 6700));
    _sustainedTimer = Timer.periodic(pulseInterval, (timer) {
      if (DateTime.now().isAfter(endTime)) {
        timer.cancel();
        _sustainedTimer = null;
        return;
      }
      unawaited(HapticFeedback.heavyImpact());
    });
  }

  void stopArrivalVibration() {
    _sustainedTimer?.cancel();
    _sustainedTimer = null;
  }
}
