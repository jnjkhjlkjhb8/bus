import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/core/firebase/crash_reporter.dart';
import 'package:wheres_the_bus/core/lifecycle/app_foreground.dart';
import 'package:wheres_the_bus/core/lifecycle/app_network.dart';

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
    Duration recoveryGrace = const Duration(seconds: 5),
    void Function(Object, StackTrace)? reportError,
    RetryDelay? retryDelay,
    ValueListenable<bool>? foreground,
    ValueListenable<bool>? online,
  }) : _source = source,
       _onData = onData,
       _onFailure = onFailure,
       _onRecovered = onRecovered,
       _maxFailures = maxFailures,
       _baseDelay = baseDelay,
       _maxDelay = maxDelay,
       _recoveryGrace = recoveryGrace,
       _reportError = reportError ?? CrashReporter.record,
       _retryDelay = retryDelay ?? _jitteredDelay,
       _foreground = foreground ?? AppForeground.value,
       _online = online ?? AppNetwork.online {
    _foreground.addListener(_onForegroundChanged);
    _online.addListener(_onOnlineChanged);
    if (_foreground.value) _listen();
  }

  final Stream<T> Function() _source;
  final void Function(T data) _onData;
  final void Function(AppError error) _onFailure;
  final void Function()? _onRecovered;
  final int _maxFailures;
  final Duration _baseDelay;
  final Duration _maxDelay;
  final Duration _recoveryGrace;
  final void Function(Object, StackTrace) _reportError;
  final RetryDelay _retryDelay;
  final ValueListenable<bool> _foreground;
  final ValueListenable<bool> _online;

  StreamSubscription<T>? _sub;
  Timer? _timer;
  Timer? _graceTimer;
  int _failures = 0;
  int _cleanCloses = 0;
  bool _notified = false;
  bool _closed = false;

  /// Backgrounding drops the open stream — see [AppForeground]. Resuming
  /// re-listens with the backoff reset, because coming back on screen is not a
  /// failure and the user is waiting for a fresh frame.
  ///
  /// A terminal error (unauthenticated, permission denied, unimplemented) stops
  /// the retry loop, but only until the next resume (FDPL-52): a router mid-
  /// restart and an expired token both produce one, and neither is a permanent
  /// fact about the endpoint. Retrying once per resume is far from re-hammering
  /// it, and without that the feed — and the notice it raised — stayed dead for
  /// the rest of the process.
  void _onForegroundChanged() {
    if (_closed) return;
    if (!_foreground.value) {
      _timer?.cancel();
      _timer = null;
      _graceTimer?.cancel();
      _graceTimer = null;
      unawaited(_sub?.cancel() ?? Future<void>.value());
      _sub = null;
      return;
    }
    if (_sub != null) return;
    _timer?.cancel();
    _timer = null;
    _failures = 0;
    _cleanCloses = 0;
    _listen();
  }

  /// The device got an interface back. Whatever backoff is pending was sized
  /// for a server problem, not for airplane mode, so skip it and dial now
  /// (FDPL-55). Only a scheduled retry is short-circuited: a live subscription
  /// is left alone, and a stream stopped by a terminal error stays stopped
  /// until the next resume.
  void _onOnlineChanged() {
    if (_closed || !_online.value || !_foreground.value) return;
    if (_sub != null || _timer == null) return;
    _timer!.cancel();
    _timer = null;
    _listen();
  }

  void _listen() {
    if (_closed || !_foreground.value) return;
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
        _markRecovered();
        _cleanCloses = 0;
        _onData(data);
      },
      onError: _handleError,
      onDone: () {
        if (_closed) return;
        _sub = null;
        // A clean close only happens on a connection that was actually
        // established, so it proves the endpoint is reachable just as a frame
        // would.
        _markRecovered();
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
    // Nothing but time proves a reconnect worked on a quiet stream: alerts sit
    // silent for hours, so waiting for a frame to declare recovery leaves the
    // offline notice up forever after the network comes back (FDPL-48).
    // Surviving [_recoveryGrace] without an error is the proof instead.
    if (_failures > 0 || _notified) {
      _graceTimer?.cancel();
      _graceTimer = Timer(_recoveryGrace, _markRecovered);
    }
  }

  /// Clears the failure state and tells the caller, once, that the feed is
  /// healthy again. A no-op when nothing had failed.
  void _markRecovered() {
    _graceTimer?.cancel();
    _graceTimer = null;
    if (_failures == 0 && !_notified) return;
    _failures = 0;
    _notified = false;
    _onRecovered?.call();
  }

  void _handleError(Object e, StackTrace s) {
    _graceTimer?.cancel();
    _graceTimer = null;
    _reportError(e, s);
    final terminal = _isTerminal(e);
    _failures = terminal ? _maxFailures : _failures + 1;
    if (_failures >= _maxFailures && !_notified) {
      _notified = true;
      _onFailure(AppError.from(e));
    }
    if (terminal) {
      // No retry is scheduled, so the loop stops here — until the next resume
      // re-listens (see [_onForegroundChanged]).
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
    _foreground.removeListener(_onForegroundChanged);
    _online.removeListener(_onOnlineChanged);
    _timer?.cancel();
    _graceTimer?.cancel();
    await _sub?.cancel();
  }

  static Duration _jitteredDelay(Duration delay) {
    final min = delay.inMilliseconds ~/ 2;
    final max = delay.inMilliseconds + min;
    return Duration(milliseconds: min + _random.nextInt(max - min + 1));
  }

  static final Random _random = Random();
}
