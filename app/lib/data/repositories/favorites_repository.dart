import 'package:hive_ce_flutter/adapters.dart';
import 'package:wheres_the_car/core/storage/hive_store.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/data/models/metro_map_models.dart';

class FavoritesRepository {
  FavoritesRepository._();

  static final FavoritesRepository instance = FavoritesRepository._();

  Box<dynamic> get _box => HiveStore.favorites;

  bool get isReady => HiveStore.favoritesReady;

  Stream<BoxEvent> watch() => _box.watch();

  List<Favorite> all() {
    if (!isReady) return const [];
    final items =
        _box.values
            .whereType<Map<dynamic, dynamic>>()
            .map(Favorite.fromMap)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    return items;
  }

  List<Favorite> pinned() => all().where((f) => f.pinned).toList();

  List<Favorite> ofType(FavoriteType type) =>
      all().where((f) => f.type == type).toList();

  bool isFavorite(String id) => isReady && _box.containsKey(id);

  Future<void> add(Favorite fav) async {
    if (_box.containsKey(fav.id)) return;
    final maxOrder = all().fold<int>(
      -1,
      (m, f) => f.order > m ? f.order : m,
    );
    await _box.put(
      fav.id,
      fav
          .copyWith(
            order: maxOrder + 1,
            createdAt: fav.createdAt == 0
                ? DateTime.now().millisecondsSinceEpoch
                : fav.createdAt,
          )
          .toMap(),
    );
  }

  Future<void> remove(String id) => _box.delete(id);

  Future<bool> toggle(Favorite fav) async {
    if (_box.containsKey(fav.id)) {
      await remove(fav.id);
      return false;
    }
    await add(fav);
    return true;
  }

  Future<void> setPinned(String id, {required bool pinned}) async {
    final raw = _box.get(id);
    if (raw is! Map) return;
    await _box.put(id, Favorite.fromMap(raw).copyWith(pinned: pinned).toMap());
  }

  Future<void> saveOrder(List<Favorite> ordered) async {
    for (final (i, f) in ordered.indexed) {
      await _box.put(f.id, f.copyWith(order: i).toMap());
    }
  }

  Future<void> migrateLegacy() async {
    final settings = HiveStore.settings;
    if (settings.get('favorites_migrated', defaultValue: false) as bool) return;

    var order = all().length;
    Future<void> put(Favorite fav) async {
      if (_box.containsKey(fav.id)) return;
      await _box.put(
        fav.id,
        fav
            .copyWith(
              order: order++,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            )
            .toMap(),
      );
    }

    final busStops = List<String>.from(
      settings.get('fav_bus_stops', defaultValue: <String>[]) as List,
    );
    for (final name in busStops) {
      await put(Favorite(type: FavoriteType.busStop, refId: name, title: name));
    }

    for (final id in HiveStore.favMetroStations) {
      final match = metroMapStations.where((s) => s.id == id);
      await put(
        Favorite(
          type: FavoriteType.metroStation,
          refId: id,
          title: match.isEmpty ? id : match.first.name,
          subtitle: '捷運',
        ),
      );
    }

    for (final key in HiveStore.favRoutes.keys) {
      final v = HiveStore.favRoutes.get(key);
      if (v is! Map) continue;
      final routeType = (v['route_type'] as String?) ?? 'bus';
      await put(
        Favorite(
          type: routeType == 'bus'
              ? FavoriteType.busRoute
              : FavoriteType.railTrain,
          refId: (v['route_key'] as String?) ?? key.toString(),
          title: (v['route_label'] as String?) ?? key.toString(),
        ),
      );
    }

    await settings.put('favorites_migrated', true);
  }
}
