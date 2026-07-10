import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:wheres_the_car/core/firebase/firebase_gate.dart';

/// Thin read accessor over Firebase Remote Config.
///
/// Callers never touch [FirebaseRemoteConfig.instance] directly: on the
/// dev/test flavor Firebase is disabled ([FirebaseGate.enabled] is false) and
/// touching the instance throws. Every getter falls back to [defaults] when
/// Firebase is off or a read fails, so a read is always safe from any layer.
class AppConfig {
  AppConfig._();
  /// Bumped whenever a Realtime Remote Config update is activated, so widgets
  /// reading config (e.g. the maintenance banner) can rebuild without a
  /// relaunch. Listen via a ValueListenableBuilder; the value itself is opaque.
  static final version = ValueNotifier<int>(0);

  /// Single source of truth for defaults. Also fed to `setDefaults()` at
  /// bootstrap so registered and fallback values can't drift apart.
  static const defaults = <String, Object>{
    'maintenance_banner_enabled': false,
    'maintenance_banner_text': '',
    'push_enabled': true,
    'min_supported_version': '1.0.0',
    'store_url_ios': '',
    'store_url_android': '',
    'arrival_lead_minutes': '1,3,5',
    'eta_approaching_threshold_s': 30,
    // Tagged tokens: `metro:<system>` and `bus:<city>`, comma-separated.
    'alert_sources': 'metro:TRTC,bus:Taipei',
    'nearby_fallback_radius_m': 900,
  };

  static bool getBool(String key) => _read(key, (rc) => rc.getBool(key));
  static String getString(String key) => _read(key, (rc) => rc.getString(key));
  static int getInt(String key) => _read(key, (rc) => rc.getInt(key));

  static T _read<T>(String key, T Function(FirebaseRemoteConfig) read) {
    if (FirebaseGate.enabled) {
      try {
        return read(FirebaseRemoteConfig.instance);
      } on Object catch (_) {
        // Fall through to the registered default.
      }
    }
    return defaults[key]! as T;
  }
}
