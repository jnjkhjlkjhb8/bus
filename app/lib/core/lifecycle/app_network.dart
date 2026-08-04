import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the device currently has a network path.
///
/// This reports the *link*, not reachability: `true` only means an interface is
/// up, so a captive portal or a dead backend still reads as online. The
/// trustworthy direction is `false` — with no interface, nothing will succeed —
/// and both consumers use it that way:
///
/// - `ResilientSubscription` skips its remaining backoff on the false→true
///   edge, so flipping airplane mode off reconnects now instead of up to 30
///   seconds later.
/// - `offlineCached` serves the cache without a doomed round-trip while it is
///   false, rather than spending a 10-second deadline first.
///
/// Defaults to `true` so a platform that never answers (or a widget test with
/// no plugin binding) behaves exactly as it did before this signal existed.
class AppNetwork {
  AppNetwork._();

  static final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  static StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Starts observing connectivity. Idempotent; called once from `App`.
  static void start({Connectivity? connectivity}) {
    if (_sub != null) return;
    final source = connectivity ?? Connectivity();
    _sub = source.onConnectivityChanged.listen(
      _apply,
      // A platform that cannot report connectivity must not pin the app to
      // "offline" — leave the optimistic default and let the RPCs decide.
      onError: (Object _) => online.value = true,
    );
    unawaited(
      source.checkConnectivity().then(_apply).catchError((Object _) {
        online.value = true;
      }),
    );
  }

  static void _apply(List<ConnectivityResult> results) {
    online.value = results.any((r) => r != ConnectivityResult.none);
  }

  @visibleForTesting
  static void reset() {
    unawaited(_sub?.cancel());
    _sub = null;
    online.value = true;
  }
}
