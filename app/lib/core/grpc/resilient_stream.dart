import 'dart:async';
import 'dart:math';

import 'package:grpc/grpc.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/core/firebase/crash_reporter.dart';

typedef RetryDelay = Duration Function(Duration delay);

class ResilientSubscription<T> {
  ResilientSubscription({
    required Stream<T> Function() source,
    required void Function(T data) onData,
    required void Function(AppError error) onFailure,
    void Function()? onRecovered,
    int maxFailures = 5,
    Duration baseDelay = const Duration(seconds: 2),
    Duration maxDelay = const Duration(seconds: 30),
    void Function(Object, StackTrace)? reportError,
    RetryDelay? retryDelay,
  }) : _source = source,
       _onData = onData,
       _onFailure = onFailure,
       _onRecovered = onRecovered,
       _maxFailures = maxFailures,
       _baseDelay = baseDelay,
       _maxDelay = maxDelay,
       _reportError = reportError ?? CrashReporter.record,
       _retryDelay = retryDelay ?? _jitteredDelay {
    _listen();
  }

  final Stream<T> Function() _source;
  final void Function(T data) _onData;
  final void Function(AppError error) _onFailure;
  final void Function()? _onRecovered;
  final int _maxFailures;
  final Duration _baseDelay;
  final Duration _maxDelay;
  final void Function(Object, StackTrace) _reportError;
  final RetryDelay _retryDelay;

  StreamSubscription<T>? _sub;
  Timer? _timer;
  int _failures = 0;
  int _cleanCloses = 0;
  bool _notified = false;
  bool _closed = false;

  void _listen() {
    if (_closed) return;
    // A source factory can fail synchronously (e.g. a gRPC client that
    // validates arguments before opening the channel) instead of returning a
    // stream that later emits an error. Both must be handled identically —
    // reported, counted, retried with the same backoff — so a bad factory
    // call doesn't silently stop reconnecting.
    final Stream<T> stream;
    try {
      stream = _source();
    } on Object catch (e, s) {
      _handleError(e, s);
      return;
    }
    _sub = stream.listen(
      (data) {
        if (_failures > 0 || _notified) {
          _failures = 0;
          _notified = false;
          _onRecovered?.call();
        }
        _cleanCloses = 0;
        _onData(data);
      },
      onError: _handleError,
      onDone: () {
        if (_closed) return;
        _sub = null;
        // A clean close is normal (server-side stream rotation), but a server
        // that closes immediately on every connect must not become a hot
        // reconnect loop: back off like errors do, capped at [_maxDelay], and
        // never surface a failure. Any received data resets the backoff.
        if (_cleanCloses < 6) _cleanCloses++;
        var delay = _baseDelay * (1 << (_cleanCloses - 1));
        if (delay > _maxDelay) delay = _maxDelay;
        _timer = Timer(_retryDelay(delay), _listen);
      },
    );
  }

  void _handleError(Object e, StackTrace s) {
    _reportError(e, s);
    final terminal = _isTerminal(e);
    _failures = terminal ? _maxFailures : _failures + 1;
    if (_failures >= _maxFailures && !_notified) {
      _notified = true;
      _onFailure(AppError.from(e));
    }
    if (terminal) {
      unawaited(_sub?.cancel() ?? Future<void>.value());
      _sub = null;
      return;
    }
    _scheduleRetry();
  }

  static bool _isTerminal(Object e) {
    if (e is! GrpcError) return false;
    return switch (e.code) {
      StatusCode.unauthenticated ||
      StatusCode.permissionDenied ||
      StatusCode.unimplemented => true,
      _ => false,
    };
  }

  void _scheduleRetry() {
    if (_closed) return;
    unawaited(_sub?.cancel() ?? Future<void>.value());
    _sub = null;
    final shift = _failures - 1 > 5 ? 5 : _failures - 1;
    var delay = _baseDelay * (1 << shift);
    if (delay > _maxDelay) delay = _maxDelay;
    _timer = Timer(_retryDelay(delay), _listen);
  }

  Future<void> cancel() async {
    _closed = true;
    _timer?.cancel();
    await _sub?.cancel();
  }

  static Duration _jitteredDelay(Duration delay) {
    final min = delay.inMilliseconds ~/ 2;
    final max = delay.inMilliseconds + min;
    return Duration(milliseconds: min + _random.nextInt(max - min + 1));
  }

  static final Random _random = Random();
}
