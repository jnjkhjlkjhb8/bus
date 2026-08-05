import 'package:flutter/services.dart';

/// Which transit network the tracked vehicle belongs to. Selects the tracker
/// glyph on the platform card; nothing else about the card varies by mode.
enum AlightTrackMode { bus, tra, thsr, metro }

/// Where the rider is in one alight-tracking session.
///
/// Replaces the four ad-hoc plugin `mode` strings (waiting / riding /
/// pinned / mrt_track) that used to render four different cards for the same
/// intent. One card, one vocabulary, five readings of it.
enum AlightTrackPhase {
  /// Not yet aboard. Progress sits at the board stop and the chip counts
  /// minutes, not stops. This is the MaaS pre-board leg, folded in.
  waiting,

  /// Aboard and travelling toward the alight stop.
  riding,

  /// Past the rider's own 提前站數 threshold — the same moment the vibration
  /// fires. Colour, not a new card.
  approaching,

  /// Terminal: reached the alight stop.
  arrived,

  /// Terminal: the vehicle binding was lost or went stale.
  lost,
}

/// One unified alight-tracking payload, shared by every transit mode and by
/// both platform surfaces (Android promoted Live Update, iOS Live Activity).
///
/// The card it drives is always the same shape — 往 [targetStation] /
/// [vehicleLabel] · 下一站 [nextStation] / 剩 [remainingStops] 站 — so bus,
/// TRA, THSR and metro can never visually drift apart.
class AlightTrackContent {
  const AlightTrackContent({
    required this.mode,
    required this.phase,
    required this.vehicleLabel,
    required this.boardStation,
    required this.targetStation,
    required this.nextStation,
    required this.hopCount,
    required this.currentIndex,
    required this.remainingStops,
    required this.leadStops,
    this.vehicleId,
    this.etaMs,
    this.etaMinutes,
    this.walkMinutes = 0,
    this.scheduledDepartureMs,
    this.delayMinutes = 0,
    this.lineCode,
    this.lineColorHex,
    this.trackId,
  });

  final AlightTrackMode mode;
  final AlightTrackPhase phase;

  /// Route or train identity as the rider reads it: `307`, `自強 408`,
  /// `高鐵 663`, `板南線`.
  final String vehicleLabel;

  /// The specific vehicle within that route — plate, or the metro carID.
  /// Null when the session tracks a route rather than one vehicle.
  final String? vehicleId;

  final String boardStation;

  /// 下車站 — the whole point of the session.
  final String targetStation;

  final String nextStation;

  /// Segments on the progress bar: one per hop from board to target. Always
  /// at least 1, so the bar never collapses to nothing.
  final int hopCount;

  /// Hops already completed, `0..hopCount`.
  final int currentIndex;

  final int remainingStops;

  /// The rider's own 提前站數. Doubles as the colour threshold: at
  /// `remainingStops <= leadStops` the bar turns amber, which is the same
  /// moment the reminder vibrates. One number, one definition of "close".
  final int leadStops;

  /// Absolute arrival time, for iOS's Live Activity — ActivityKit renders its
  /// own live timer and needs a target date to do it. Null once stops carry
  /// the reading.
  final int? etaMs;

  /// The same arrival, as the minutes the backend actually reported.
  ///
  /// Android's chip prints this verbatim rather than deriving minutes from
  /// [etaMs] against the device clock: derived, the number would drift on
  /// every re-render even when no new data had arrived, which reads as a
  /// countdown the feed is not backing. Stale-but-honest beats live-but-made
  /// up — the card should only move when the data does.
  final int? etaMinutes;

  /// Walk to the board stop, minutes. Only meaningful while
  /// [AlightTrackPhase.waiting]; 0 everywhere else.
  final int walkMinutes;

  /// Timetabled departure from [boardStation], and the live delay against it.
  ///
  /// Rail only, and only while [AlightTrackPhase.waiting]: a train the rider
  /// has not caught yet is described by its timetable, not by a stop count.
  /// The two travel separately rather than pre-added so the card can say
  /// "08:20 開 · 誤點 5 分" — a rider checks the printed time against the board
  /// and needs the slip named, not silently folded in.
  final int? scheduledDepartureMs;
  final int delayMinutes;

  /// The line's identity as data: its code (`BL`, `R`) and colour. Android
  /// deliberately does not render these — its bar colour encodes distance to
  /// the alight stop instead — but the payload carries them because iOS's
  /// Live Activity draws a line roundel from them. Null off the metro.
  final String? lineCode;
  final String? lineColorHex;

  /// The server session this card belongs to, so Android's 取消追蹤 can end it
  /// even from a process with no Dart left alive (FDPL-65). Null off the metro:
  /// a bus or rail ride's session exists only on this device, and there is
  /// nothing to cancel anywhere else.
  final String? trackId;

  Map<String, Object?> toArgs() => {
    'mode': mode.name,
    'phase': phase.name,
    'vehicleLabel': vehicleLabel,
    'vehicleId': vehicleId,
    'boardStation': boardStation,
    'targetStation': targetStation,
    'nextStation': nextStation,
    'hopCount': hopCount,
    'currentIndex': currentIndex,
    'remainingStops': remainingStops,
    'leadStops': leadStops,
    'etaMs': etaMs,
    'etaMinutes': etaMinutes,
    'walkMinutes': walkMinutes,
    'scheduledDepartureMs': scheduledDepartureMs,
    'delayMinutes': delayMinutes,
    'lineCode': lineCode,
    'lineColorHex': lineColorHex,
    'trackId': trackId,
  };
}

/// Thin wrapper over the platform alight-tracking channel. All platform
/// errors are swallowed: a broken system card must never break navigation.
///
/// Only one tracking card can exist at a time, shared across the journey
/// session bloc and the metro track bloc, so [start] hands back a lease
/// number identifying "this call's" card. Callers must pass that lease back
/// into [update]/[stop]; a command carrying a lease that is no longer the
/// active one is a silent no-op. This is what stops a delayed command from a
/// superseded owner (e.g. an old journey's `stop()`, dispatched before a new
/// journey took over) from clobbering whatever started after it.
///
/// Every command additionally funnels through an internal queue so the
/// underlying `MethodChannel.invokeMethod` calls always reach the platform
/// side in the order callers issued them — without that, two in-flight calls
/// (e.g. a stale `stop` and a fresh `start`) could race and land out of order
/// even though the lease on the stale one was already stale when queued.
class AlightTrackChannel {
  static const _channel = MethodChannel('com.wheres.bus/live_activity');

  int _nextLease = 0;
  int? _activeLease;
  Future<void> _queue = Future<void>.value();

  Future<int> start(AlightTrackContent content) {
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

  Future<void> update(int lease, AlightTrackContent content) {
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
