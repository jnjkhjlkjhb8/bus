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

/// One route row on the stop-board Live Activity.
class StopBoardRow {
  const StopBoardRow({
    required this.routeNumber,
    required this.destination,
    required this.etaLabel,
  });

  final String routeNumber;
  final String destination;
  final String etaLabel;

  Map<String, Object?> toArgs() => {
    'route': routeNumber,
    'destination': destination,
    'eta': etaLabel,
  };
}

/// Thin wrapper over the platform live-activity channel. All platform errors
/// are swallowed: a broken lock-screen card must never break navigation.
///
/// Only one Live Activity can exist at a time, shared across the journey
/// session bloc and the stop-board driver, so [start]/[startBoard] hand
/// back a lease number that identifies "this call's" activity. Callers
/// must pass that lease back into [update]/[updateBoard]/[stop]; a command
/// carrying a lease that is no longer the active one is a silent no-op. This
/// is what stops a delayed command from a superseded owner (e.g. an old
/// journey's `stop()`, dispatched before a new journey or a stop-board took
/// over) from clobbering whatever started after it.
///
/// Every command additionally funnels through an internal queue so the
/// underlying `MethodChannel.invokeMethod` calls always reach the platform
/// side in the same order callers issued them — without that, two
/// in-flight calls (e.g. a stale `stop` and a fresh `start`) could race and
/// land out of order even though the lease on the stale one was already
/// stale by the time it was queued.
class LiveActivityChannel {
  static const _channel = MethodChannel('com.wheres.bus/live_activity');

  int _nextLease = 0;
  int? _activeLease;
  Future<void> _queue = Future<void>.value();

  Future<int> start(LiveActivityContent content) {
    final lease = ++_nextLease;
    return _enqueue(() async {
      _activeLease = lease;
      try {
        await _channel.invokeMethod<String>('start', content.toArgs());
      } on PlatformException {
        _releaseIfCurrent(lease);
      } on MissingPluginException {
        _releaseIfCurrent(lease);
      }
    }).then((_) => lease);
  }

  Future<void> update(int lease, LiveActivityContent content) {
    return _enqueue(() async {
      if (!_isActive(lease)) return; // stale: superseded before this ran
      try {
        await _channel.invokeMethod<void>('update', content.toArgs());
      } on PlatformException {
        // keep session alive; next update retries
      } on MissingPluginException {
        _releaseIfCurrent(lease);
      }
    });
  }

  Future<int> startBoard(String stopName, List<StopBoardRow> rows) {
    final lease = ++_nextLease;
    return _enqueue(() async {
      _activeLease = lease;
      try {
        await _channel.invokeMethod<String>('start', {
          'mode': 'board',
          'stopName': stopName,
          'routes': [for (final row in rows) row.toArgs()],
        });
      } on PlatformException {
        _releaseIfCurrent(lease);
      } on MissingPluginException {
        _releaseIfCurrent(lease);
      }
    }).then((_) => lease);
  }

  Future<void> updateBoard(
    int lease,
    String stopName,
    List<StopBoardRow> rows,
  ) {
    return _enqueue(() async {
      if (!_isActive(lease)) return; // stale: superseded before this ran
      try {
        await _channel.invokeMethod<void>('update', {
          'mode': 'board',
          'stopName': stopName,
          'routes': [for (final row in rows) row.toArgs()],
        });
      } on PlatformException {
        // keep session alive; next update retries
      } on MissingPluginException {
        _releaseIfCurrent(lease);
      }
    });
  }

  Future<void> stop(int lease) {
    return _enqueue(() async {
      if (!_isActive(lease)) return; // stale: already superseded
      _activeLease = null;
      try {
        await _channel.invokeMethod<void>('stop');
      } on PlatformException {
        // already gone — nothing to clean up
      } on MissingPluginException {
        // no-op
      }
    });
  }

  bool _isActive(int lease) => _activeLease == lease;

  void _releaseIfCurrent(int lease) {
    if (_activeLease == lease) _activeLease = null;
  }

  /// Chains [op] onto the tail of the command queue so platform calls fire
  /// in call order regardless of how their individual futures interleave.
  Future<T> _enqueue<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}
