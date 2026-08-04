import 'dart:async';

import 'package:protobuf/protobuf.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/core/lifecycle/app_network.dart';
import 'package:wheres_the_bus/core/storage/hive_store.dart';

/// Runs [fetch], caches the verbatim response bytes, and falls back to the
/// last cached response when the network is unreachable (ADR-0017).
///
/// Network-first while a network exists. Two things short-circuit it: a
/// device with no interface up at all (see [AppNetwork]), and [maxAge].
/// Without [maxAge] the cache is otherwise only consulted from the `catch`, so
/// online behaviour is exactly what it was
/// before any call site adopted this. With it, an entry younger than [maxAge]
/// is returned without a round-trip at all — only for data the daily load can
/// be trusted not to move underneath, since nothing revalidates in the
/// background. Serialization lives here rather than in `HiveStore` so
/// generated proto types stay inside `app/lib/data/`, as CONTEXT.md requires.
///
/// [key] must start with `s:` for entries whose validity is open-ended, or
/// `d:<yyyy-MM-dd>:` for entries that only describe one service date — the
/// prefix is what [HiveStore.pruneStaticCache] sweeps on.
Future<T> offlineCached<M extends GeneratedMessage, T>({
  required String key,
  required Future<M> Function() fetch,
  required M Function(List<int>) parse,
  required T Function(M) decode,
  Duration? maxAge,
}) async {
  if (maxAge != null) {
    final fresh = HiveStore.getStaticFresh(key, maxAge);
    if (fresh != null) {
      try {
        return decode(parse(fresh));
      } on Object {
        // Bytes an older build wrote in a shape this one cannot read. Drop
        // them and fall through to the network — unlike the offline branch
        // below there is a live request available, so nothing is lost.
        unawaited(HiveStore.deleteStatic(key));
      }
    }
  }
  // With no interface up, the request is going to spend its whole 10-second
  // deadline before failing into the `catch` below — ten seconds per query,
  // on every screen, for an answer already on disk (FDPL-56). Only the
  // "definitely offline" direction of the signal is trusted, so this can
  // never mask a reachable server. Falls through when nothing is cached: the
  // caller still needs the real error.
  if (!AppNetwork.online.value) {
    final bytes = HiveStore.getStatic(key);
    if (bytes != null) {
      try {
        return decode(parse(bytes));
      } on Object {
        unawaited(HiveStore.deleteStatic(key));
      }
    }
  }
  try {
    final message = await fetch();
    // Unawaited: a full disk must not fail a request that already succeeded.
    unawaited(HiveStore.putStatic(key, message.writeToBuffer()));
    return decode(message);
  } on Object catch (error, stack) {
    if (!_isReachabilityFailure(error)) rethrow;
    final bytes = HiveStore.getStatic(key);
    if (bytes == null) rethrow;
    try {
      return decode(parse(bytes));
    } on Object {
      // Bytes written by an incompatible build, or a truncated write. This
      // runs when the rider is *already* offline, so a decode failure must
      // degrade to the network error they would have seen anyway — never
      // replace a handled error with a crash.
      unawaited(HiveStore.deleteStatic(key));
      Error.throwWithStackTrace(error, stack);
    }
  }
}

/// Only an unreachable server justifies serving a cached answer. A `NotFound`
/// or a server-side error means the backend *did* reply, and overriding a
/// definitive answer with a stale one would be a worse lie than the error.
bool _isReachabilityFailure(Object error) => switch (AppError.from(error)) {
  OfflineError() || TimeoutError() => true,
  _ => false,
};
