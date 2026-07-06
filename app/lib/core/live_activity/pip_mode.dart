import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android picture-in-picture bridge. iOS: both methods are no-ops
/// (MissingPluginException swallowed) and [isPip] stays false.
class PipMode {
  PipMode._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        isPip.value = call.arguments as bool? ?? false;
      }
    });
  }

  static final PipMode instance = PipMode._();
  static const _channel = MethodChannel('com.jnjk.bus/pip');

  final ValueNotifier<bool> isPip = ValueNotifier(false);

  // Positional bool mirrors the native channel's single-argument signature.
  // ignore: avoid_positional_boolean_parameters
  Future<void> setNavigating(bool value) async {
    try {
      await _channel.invokeMethod<void>('setNavigating', value);
    } on MissingPluginException {
      // iOS / tests
    }
  }
}
