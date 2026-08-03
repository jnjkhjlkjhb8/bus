import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wheres_the_bus/data/models/subscription_scope.dart';
import 'package:wheres_the_bus/data/repositories/favorites_repository.dart';
import 'package:wheres_the_bus/data/repositories/firebase_repository.dart';

/// Keeps the server's copy of this device's 訂閱範圍 equal to what 收藏
/// currently resolves to. It is the single write path — no screen syncs a
/// subscription of its own — so a 收藏 removed from the favourites list, or
/// restored onto a fresh install, converges on the next push instead of
/// leaving the server pushing alerts for routes the rider no longer has.
///
/// The collaborators are plain functions rather than the repositories so the
/// loop can be exercised without Hive or gRPC.
class SubscriptionSync {
  SubscriptionSync({
    required Stream<void> Function() changes,
    required Set<String> Function() currentScope,
    required Future<void> Function(Set<String>) replace,
  }) : _changes = changes,
       _currentScope = currentScope,
       _replace = replace;

  static final SubscriptionSync instance = SubscriptionSync(
    changes: FavoritesRepository.instance.changes,
    currentScope: () => subscriptionScope(FavoritesRepository.instance.all()),
    replace: FirebaseRepository.instance.replaceRouteSubscriptions,
  );

  final Stream<void> Function() _changes;
  final Set<String> Function() _currentScope;
  final Future<void> Function(Set<String>) _replace;

  StreamSubscription<void>? _sub;
  Set<String>? _sent;
  bool _sending = false;
  bool _stale = false;

  /// Begins syncing, and pushes the current scope once. Call only after the
  /// device row exists: the subscription rows reference it, so an earlier call
  /// would be rejected. Calling again only forces one extra refresh.
  void start() {
    _sub ??= _changes().listen((_) => unawaited(push()));
    unawaited(push());
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Sends the current scope unless the server already has it. Sends are
  /// serialized: two replaces racing could land out of order and leave the
  /// server holding the older set, so a change arriving mid-flight re-runs the
  /// loop rather than starting a second call.
  @visibleForTesting
  Future<void> push() async {
    if (_sending) {
      _stale = true;
      return;
    }
    _sending = true;
    try {
      do {
        _stale = false;
        final scope = _currentScope();
        if (setEquals(scope, _sent)) break;
        await _replace(scope);
        _sent = scope;
      } while (_stale);
    } on Object catch (_) {
      // Drop what we believed the server had, so the next attempt resends even
      // if 收藏 is back at the last successfully stored scope.
      _sent = null;
    } finally {
      _sending = false;
    }
  }
}
