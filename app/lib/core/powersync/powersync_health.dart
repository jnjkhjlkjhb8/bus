import 'dart:async';

/// Owns the single subscription to a PowerSync-style status stream and
/// forwards de-duplicated errors to [onError].
///
/// Generic over the source element type `T` so the dedupe/ownership logic is
/// testable with a plain `Stream<String?>` fixture instead of the real
/// `powersync` package's `SyncStatus` (whose constructor is `@internal` and
/// off-limits outside that package). `PowerSyncService` instantiates this
/// with `T = SyncStatus` and
/// `errorOf: (s) => s.downloadError ?? s.uploadError`.
class PowerSyncHealth<T> {
  PowerSyncHealth({required this.errorOf, required this.onError});

  /// Extracts the current error (or `null` when healthy) from a status
  /// event.
  final Object? Function(T status) errorOf;

  /// Called with each newly observed, non-repeated error.
  final void Function(Object error) onError;

  StreamSubscription<T>? _subscription;
  String? _lastErrorKey;

  /// Subscribes to [stream], replacing any subscription owned by this
  /// instance. Safe to call repeatedly (e.g. on PowerSync re-init): the
  /// previous subscription is always cancelled first so a reinit never
  /// leaks a listener.
  void listen(Stream<T> stream) {
    unawaited(_subscription?.cancel());
    _lastErrorKey = null;
    _subscription = stream.listen((status) {
      final error = errorOf(status);
      if (error == null) {
        _lastErrorKey = null;
        return;
      }
      final key = error.toString();
      if (key == _lastErrorKey) return;
      _lastErrorKey = key;
      onError(error);
    });
  }

  /// Cancels the owned subscription, if any. Call from `close()`/`dispose()`
  /// so a service teardown never leaves a dangling listener.
  Future<void> cancel() async {
    await _subscription?.cancel();
    _subscription = null;
    _lastErrorKey = null;
  }
}
