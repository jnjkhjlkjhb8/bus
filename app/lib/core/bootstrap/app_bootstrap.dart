import 'dart:async';

import 'package:flutter/foundation.dart';

/// Lifecycle of the app's background bootstrap work.
///
/// `initializing` is the state at the moment `runApp` returns: the first
/// frame must never wait for any of it. `ready` means the essential path
/// (local storage + the gRPC channel config) is usable. `degraded` means the
/// essential path is usable but a best-effort dependency (Firebase,
/// PowerSync) failed — the app runs, offline/without those features.
/// `failed` means an essential dependency failed and the app cannot safely
/// proceed until `AppBootstrapController.retry` succeeds.
enum AppBootstrapState { initializing, ready, degraded, failed }

enum AppBootstrapFailurePhase { storage, network }

/// Drives app startup off the `runApp` critical path.
///
/// Hive, the gRPC channel config, Firebase, and PowerSync all involve
/// filesystem or network I/O with no fixed upper bound, so `main()` must not
/// `await` them before calling `runApp` (F11/F12). This controller runs that
/// work in the background and exposes a small state machine the UI can
/// listen to instead.
///
/// Hive and gRPC config validation are treated as essential: without local
/// storage or a valid channel, most of the app cannot function, so a
/// failure there fails closed rather than rendering a broken UI (`failed`).
/// Firebase and PowerSync are best-effort: their failure only degrades
/// optional features (push, sync, crash reporting), so it moves an
/// already-`ready` app to `degraded` rather than blocking it.
class AppBootstrapController extends ChangeNotifier {
  AppBootstrapController({
    required Future<void> Function() initHive,
    required Future<void> Function() initGrpc,
    required Future<void> Function() initFirebase,
    required Future<void> Function() initPowerSync,
  }) : _initHive = initHive,
       _initGrpc = initGrpc,
       _initFirebase = initFirebase,
       _initPowerSync = initPowerSync;

  final Future<void> Function() _initHive;
  final Future<void> Function() _initGrpc;
  final Future<void> Function() _initFirebase;
  final Future<void> Function() _initPowerSync;

  AppBootstrapState _state = AppBootstrapState.initializing;
  AppBootstrapState get state => _state;

  /// The error from the most recent failed essential-init attempt, if any.
  Object? lastError;

  /// Which essential step [lastError] came from. Null whenever [lastError]
  /// is null.
  AppBootstrapFailurePhase? lastErrorPhase;

  bool _bestEffortFailed = false;

  /// Runs the essential path and fires the best-effort steps alongside it.
  /// Safe to call once from `main()` right before `runApp`; it never
  /// throws.
  Future<void> start() async {
    unawaited(_runBestEffort(_initFirebase, 'firebase'));
    unawaited(_runBestEffort(_initPowerSync, 'powersync'));
    await _runEssential();
  }

  /// Re-attempts the essential path after a [AppBootstrapState.failed]
  /// state (or simply to force a re-check). Does not re-run the
  /// best-effort steps; callers can restart those independently once
  /// [state] is [AppBootstrapState.ready] again.
  Future<void> retry() => _runEssential();

  Future<void> _runEssential() async {
    _setState(AppBootstrapState.initializing);
    final results = await Future.wait([
      _guardEssential(_initHive, AppBootstrapFailurePhase.storage),
      _guardEssential(_initGrpc, AppBootstrapFailurePhase.network),
    ]);
    for (final result in results) {
      if (result.error == null) continue;
      lastError = result.error;
      lastErrorPhase = result.phase;
      _setState(AppBootstrapState.failed);
      return;
    }
    lastError = null;
    lastErrorPhase = null;
    _setState(
      _bestEffortFailed ? AppBootstrapState.degraded : AppBootstrapState.ready,
    );
  }

  Future<({Object? error, AppBootstrapFailurePhase? phase})> _guardEssential(
    Future<void> Function() step,
    AppBootstrapFailurePhase phase,
  ) async {
    try {
      await step();
      return (error: null, phase: null);
    } on Object catch (error) {
      return (error: error, phase: phase);
    }
  }

  Future<void> _runBestEffort(
    Future<void> Function() step,
    String label,
  ) async {
    try {
      await step();
    } on Object catch (error) {
      // A best-effort dependency can fail before or after the essential
      // path settles (they race). Either way, remember it and degrade an
      // already-ready app immediately, or let `_runEssential` land on
      // `degraded` instead of `ready` once it catches up.
      _bestEffortFailed = true;
      debugPrint('[bootstrap] $label failed (best-effort, degraded): $error');
      if (_state == AppBootstrapState.ready) {
        _setState(AppBootstrapState.degraded);
      }
    }
  }

  void _setState(AppBootstrapState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }
}
