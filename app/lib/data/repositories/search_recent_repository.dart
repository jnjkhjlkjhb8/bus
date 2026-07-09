import 'package:wheres_the_car/core/storage/hive_store.dart';
import 'package:wheres_the_car/data/models/search_models.dart';

class SearchRecentRepository {
  const SearchRecentRepository._();
  static const instance = SearchRecentRepository._();

  static const _key = 'recent_search_results';
  static const _maxItems = 8;

  List<SearchResult> all() {
    if (!HiveStore.settingsReady) return const [];
    final raw = HiveStore.settings.get(_key, defaultValue: <dynamic>[]);
    if (raw is! List) return const [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(_fromMap)
        .whereType<SearchResult>()
        .toList(growable: false);
  }

  Future<void> add(SearchResult result) async {
    if (!HiveStore.settingsReady) return;
    final current = all()
        .where((r) => r.type != result.type || r.uid != result.uid)
        .toList();
    final next = [result, ...current].take(_maxItems).map(_toMap).toList();
    await HiveStore.settings.put(_key, next);
  }

  Future<void> remove(SearchResult result) async {
    if (!HiveStore.settingsReady) return;
    final next = all()
        .where((r) => r.type != result.type || r.uid != result.uid)
        .map(_toMap)
        .toList();
    await HiveStore.settings.put(_key, next);
  }

  Future<void> clear() async {
    if (!HiveStore.settingsReady) return;
    await HiveStore.settings.delete(_key);
  }

  Map<String, Object?> _toMap(SearchResult result) => {
    'type': result.type.name,
    'uid': result.uid,
    'name': result.name,
    'subtitle': result.subtitle,
    'city': result.city,
    'lat': result.lat,
    'lon': result.lon,
  };

  SearchResult? _fromMap(Map<dynamic, dynamic> map) {
    final typeName = map['type'] as String?;
    final type = SearchResultType.values.where((t) => t.name == typeName);
    if (type.isEmpty) return null;
    final uid = map['uid'] as String? ?? '';
    final name = map['name'] as String? ?? '';
    if (uid.isEmpty || name.isEmpty) return null;
    return SearchResult(
      type: type.first,
      uid: uid,
      name: name,
      subtitle: map['subtitle'] as String? ?? '',
      city: map['city'] as String?,
      lat: (map['lat'] as num?)?.toDouble(),
      lon: (map['lon'] as num?)?.toDouble(),
    );
  }
}
