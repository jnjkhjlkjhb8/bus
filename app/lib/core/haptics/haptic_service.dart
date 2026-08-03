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

  /// 提前提醒站 — "heads up, one more to go" (ADR-0020).
  ///
  /// Two medium impacts a beat apart. Two beats read as intentional where a
  /// single one reads as a stray notification, and medium rather than heavy
  /// because this is information, not a summons — the stop it warns about is
  /// not the stop the rider gets off at.
  Future<void> shortAlightPulse() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.mediumImpact();
  }

  /// 下車站 is next — the one the rider is actually waiting for (ADR-0020).
  ///
  /// Heavy impacts every 130 ms for 1.6 s. At that spacing the pulses fuse
  /// into one continuous buzz instead of reading as counted taps, which is
  /// what makes it distinguishable from [shortAlightPulse] through a coat
  /// pocket without either one having to be louder.
  void longAlightPulse() {
    _sustainedTimer?.cancel();
    const pulseInterval = Duration(milliseconds: 130);
    final endTime = DateTime.now().add(const Duration(milliseconds: 1600));
    unawaited(HapticFeedback.heavyImpact());
    _sustainedTimer = Timer.periodic(pulseInterval, (timer) {
      if (DateTime.now().isAfter(endTime)) {
        timer.cancel();
        _sustainedTimer = null;
        return;
      }
      unawaited(HapticFeedback.heavyImpact());
    });
  }

  void stopAlightPulse() {
    _sustainedTimer?.cancel();
    _sustainedTimer = null;
  }
}
