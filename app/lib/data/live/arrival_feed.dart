import 'dart:async';

import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/grpc/resilient_stream.dart';

/// Merges a fresh server frame into the current list, returning the next list.
/// Returning the same instance as `current` signals "no change" so the feed
/// skips the emission (e.g. an empty replace frame while entries exist).
typedef _Merge<T> = List<T> Function(List<T> current, List<T> frame);

/// Distinguishes a fresh network frame from a local decay re-emission.
/// Consumers (blocs) use this to decide what an emission is allowed to touch:
/// only `source` frames represent new information from the server and may
/// refresh network-freshness timestamps or clear an offline error; `decay`
/// re-emissions only re-derive already-known values (e.g. a countdown ticking
/// down) and must leave freshness/error state untouched (F29, F30).
enum ArrivalFeedEmissionKind { source, decay }

/// One [watch] emission: the merged/decayed arrival list plus which kind of
/// event produced it. See [ArrivalFeedEmissionKind] for what each kind means
/// to a consumer.
class ArrivalFeedEmission<T> {
  const ArrivalFeedEmission(this.arrivals, this.kind);

  final List<T> arrivals;
  final ArrivalFeedEmissionKind kind;

  bool get isSource => kind == ArrivalFeedEmissionKind.source;
  bool get isDecay => kind == ArrivalFeedEmissionKind.decay;
}

/// The deep live-arrival module (CONTEXT.md: "arrival feed"). One interface,
/// [watch], turns a raw server stream of arrival frames into a merged, decayed,
/// sorted stream of arrival lists. It hides four concerns every live-arrival
/// bloc used to hand-wire: reconnect/backoff (delegated to
/// [ResilientSubscription] — never reimplemented here), decay ticking between
/// server frames, the merge policy, and sorting. Blocs shrink to forwarding the
/// output into state.
///
/// Two merge policies form a small closed set, selected by named constructor:
/// [ArrivalFeed.replace] (each frame replaces the whole list — bus) and
/// [ArrivalFeed.upsertByKey] (each frame updates the entries it carries, keyed
/// by e.g. line+destination — metro).
///
/// Decay orchestration lives here, but the decay *rule* stays in the model's
/// `decayed(now)` (backed by eta_format.dart): the feed only calls the
/// supplied decay function on a timer so countdowns stay accurate between
/// frames. Modes without decay semantics pass no decay function; no timer runs.
class ArrivalFeed<T> {
  ArrivalFeed._({
    required _Merge<T> merge,
    required T Function(T item, DateTime now)? decay,
    required Duration decayInterval,
  }) : _merge = merge,
       _decay = decay,
       _decayInterval = decayInterval;

  /// Replace policy: each server frame replaces the whole list. An empty frame
  /// is ignored while entries already exist, preserving the last good list
  /// (matches the bus blocs' `_onUpdated` empty-frame guard exactly).
  ///
  /// [decay] re-derives each entry against `now` between frames; omit it for
  /// modes without decay semantics. [decayInterval] defaults to the 15s tick
  /// the bus blocs used. [compare], when supplied, sorts each replaced frame —
  /// the whole-list analogue of [ArrivalFeed.upsertByKey]'s `compare`, letting
  /// a full-replace source (TRA's departure board) fold its sort into the feed
  /// instead of re-sorting in the bloc.
  factory ArrivalFeed.replace({
    T Function(T item, DateTime now)? decay,
    int Function(T a, T b)? compare,
    Duration decayInterval = const Duration(seconds: 15),
  }) => ArrivalFeed._(
    merge: (current, frame) {
      // Empty-frame guard: keep the last good list when a frame arrives empty
      // but entries already exist. Mirrors the bus blocs' original _onUpdated.
      if (frame.isEmpty && current.isNotEmpty) return current;
      if (compare == null) return frame;
      return [...frame]..sort(compare);
    },
    decay: decay,
    decayInterval: decayInterval,
  );

  /// Upsert-by-key policy: each frame's entries update (or insert) the entry at
  /// their [key], accumulating across frames. Output is sorted by [compare].
  /// Used by metro, whose source pushes one arrival per frame keyed by
  /// line+destination.
  ///
  /// [decay] and [decayInterval] behave as in [ArrivalFeed.replace]; metro
  /// passes no decay function (its estimates are already minute-ceiled with no
  /// absolute instant to decay).
  factory ArrivalFeed.upsertByKey({
    required Object Function(T item) key,
    required int Function(T a, T b) compare,
    T Function(T item, DateTime now)? decay,
    Duration decayInterval = const Duration(seconds: 15),
  }) => ArrivalFeed._(
    merge: (current, frame) {
      if (frame.isEmpty) return current;
      final byKey = {for (final item in current) key(item): item};
      for (final item in frame) {
        byKey[key(item)] = item;
      }
      return byKey.values.toList()..sort(compare);
    },
    decay: decay,
    decayInterval: decayInterval,
  );

  /// Resilient passthrough for a single live value that is NOT an arrival list
  /// — bike availability, one alert, a delay map. It reuses this module's one
  /// [ResilientSubscription] seam (reconnect/backoff, terminal-error handling)
  /// but adds no arrival semantics: no merge, no decay, no sort. Each source
  /// value is forwarded verbatim. This is the identity policy that lets every
  /// live stream — arrival lists and lone values alike — pass through the same
  /// module, so there is one live-stream seam over gRPC rather than two.
  ///
  /// Returns a stream the caller listens to and cancels via the returned
  /// [StreamSubscription]; cancelling stops the source. [onFailure] fires when
  /// the underlying subscription gives up; [onRecovered] fires when it recovers
  /// after a failure notification.
  static Stream<V> passthrough<V>({
    required Stream<V> Function() source,
    void Function(AppError error)? onFailure,
    void Function()? onRecovered,
  }) {
    final controller = StreamController<V>();
    ResilientSubscription<V>? sub;

    controller
      ..onListen = () {
        sub = ResilientSubscription<V>(
          source: source,
          onData: (value) {
            if (!controller.isClosed) controller.add(value);
          },
          onFailure: (e) => onFailure?.call(e),
          onRecovered: onRecovered,
        );
      }
      ..onCancel = () async {
        await sub?.cancel();
      };

    return controller.stream;
  }

  final _Merge<T> _merge;
  final T Function(T item, DateTime now)? _decay;
  final Duration _decayInterval;

  /// Subscribes to [source] and returns a stream of merged/sorted arrival
  /// lists. Reconnect, decay ticking, merging, and sorting all live below this
  /// seam; the caller only forwards each emitted list into state.
  ///
  /// Every emission means displayed values changed: a decay tick that leaves
  /// every entry value-equal to the current list is suppressed, so blocs can
  /// forward each emission into state without re-checking for no-op ticks.
  ///
  /// [source] yields raw server frames (a list of arrivals per frame). Single-
  /// item sources adapt with `.map((a) => [a])`. [onFailure] fires when the
  /// underlying subscription gives up (surfaced as an error state by the bloc);
  /// [onRecovered] fires when it recovers after a failure notification. Cancel
  /// the returned subscription (or the wrapping bloc's own cancel) to stop the
  /// source, the decay timer, and all emission.
  Stream<ArrivalFeedEmission<T>> watch({
    required Stream<List<T>> Function() source,
    void Function(AppError error)? onFailure,
    void Function()? onRecovered,
  }) {
    final controller = StreamController<ArrivalFeedEmission<T>>();
    var current = <T>[];
    ResilientSubscription<List<T>>? sub;
    Timer? decayTimer;

    void emit(List<T> next, ArrivalFeedEmissionKind kind) {
      current = next;
      if (!controller.isClosed) {
        controller.add(ArrivalFeedEmission<T>(current, kind));
      }
    }

    controller
      ..onListen = () {
        sub = ResilientSubscription<List<T>>(
          source: source,
          onData: (frame) {
            final merged = _merge(current, frame);
            // A no-op merge (e.g. an empty replace frame) must not emit, so the
            // last good list stays put and downstream equality checks hold.
            if (identical(merged, current)) return;
            emit(merged, ArrivalFeedEmissionKind.source);
          },
          onFailure: (e) => onFailure?.call(e),
          onRecovered: onRecovered,
        );
        final decay = _decay;
        if (decay != null) {
          decayTimer = Timer.periodic(_decayInterval, (_) {
            if (current.isEmpty) return;
            final now = DateTime.now();
            final next = [for (final item in current) decay(item, now)];
            // A decay tick re-derives every entry, but most ticks leave every
            // displayed value where it was (static entries decay to `this`,
            // already-arrived countdowns clamp at 0). Emit only when a value
            // actually moved, so an emission means the display changed and
            // downstream equality holds. Value-equal item types (Equatable / ==)
            // let this suppress; types without == fall back to identity and so
            // always re-emit, which is safe but does not suppress.
            var changed = false;
            for (var i = 0; i < next.length; i++) {
              if (next[i] != current[i]) {
                changed = true;
                break;
              }
            }
            if (!changed) return;
            // A decay tick re-derives already-known values locally; it never
            // learned anything new from the network, so it is tagged `decay`
            // (not `source`) — consumers must not treat it as fresh (F29, F30).
            emit(next, ArrivalFeedEmissionKind.decay);
          });
        }
      }
      ..onCancel = () async {
        decayTimer?.cancel();
        await sub?.cancel();
      };

    return controller.stream;
  }
}
