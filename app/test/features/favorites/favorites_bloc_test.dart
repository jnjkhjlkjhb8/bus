import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/data/repositories/favorites_repository.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_event.dart';

void main() {
  test('refresh loads repository items when ready', () async {
    final repo = _FakeFavoritesRepository(items: [_favorite('stop-1')]);
    final bloc = FavoritesBloc(repo, ValueNotifier(true));
    addTearDown(bloc.close);

    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.items, hasLength(1));
  });

  test('toggle changes the collection', () async {
    final repo = _FakeFavoritesRepository();
    final bloc = FavoritesBloc(repo, ValueNotifier(true));
    addTearDown(bloc.close);

    bloc.add(FavoriteToggled(_favorite('stop-1')));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.contains('busStop:stop-1'), isTrue);
  });

  test('remove deletes an item', () async {
    final repo = _FakeFavoritesRepository(items: [_favorite('stop-1')]);
    final bloc = FavoritesBloc(repo, ValueNotifier(true));
    addTearDown(bloc.close);

    await Future<void>.delayed(Duration.zero);
    bloc.add(const FavoriteRemoved('busStop:stop-1'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.contains('busStop:stop-1'), isFalse);
  });

  test('pin changed updates item pinned state', () async {
    final repo = _FakeFavoritesRepository(items: [_favorite('stop-1')]);
    final bloc = FavoritesBloc(repo, ValueNotifier(true));
    addTearDown(bloc.close);

    await Future<void>.delayed(Duration.zero);
    bloc.add(const FavoritePinChanged('busStop:stop-1', pinned: true));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.pinned, hasLength(1));
  });
}

Favorite _favorite(String refId) => Favorite(
  type: FavoriteType.busStop,
  refId: refId,
  title: refId,
);

class _FakeFavoritesRepository implements FavoritesRepository {
  _FakeFavoritesRepository({List<Favorite> items = const []})
    : _items = {for (final item in items) item.id: item};

  final Map<String, Favorite> _items;
  final _events = StreamController<BoxEvent>.broadcast();

  void _notify(String id, {bool deleted = false}) {
    _events.add(BoxEvent(id, _items[id]?.toMap(), deleted));
  }

  @override
  bool get isReady => true;

  @override
  Stream<BoxEvent> watch() => _events.stream;

  @override
  List<Favorite> all() =>
      _items.values.toList()..sort((a, b) => a.order.compareTo(b.order));

  @override
  List<Favorite> pinned() => all().where((f) => f.pinned).toList();

  @override
  List<Favorite> ofType(FavoriteType type) =>
      all().where((f) => f.type == type).toList();

  @override
  bool isFavorite(String id) => _items.containsKey(id);

  @override
  Future<void> add(Favorite fav) async {
    _items[fav.id] = fav;
    _notify(fav.id);
  }

  @override
  Future<void> remove(String id) async {
    _items.remove(id);
    _notify(id, deleted: true);
  }

  @override
  Future<bool> toggle(Favorite fav) async {
    if (_items.containsKey(fav.id)) {
      await remove(fav.id);
      return false;
    }
    await add(fav);
    return true;
  }

  @override
  Future<void> setPinned(String id, {required bool pinned}) async {
    final current = _items[id];
    if (current == null) return;
    _items[id] = current.copyWith(pinned: pinned);
    _notify(id);
  }

  @override
  Future<void> saveOrder(List<Favorite> ordered) async {
    for (final (index, favorite) in ordered.indexed) {
      _items[favorite.id] = favorite.copyWith(order: index);
      _notify(favorite.id);
    }
  }

  @override
  Future<void> migrateLegacy() async {}
}
