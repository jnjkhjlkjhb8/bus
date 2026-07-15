import 'package:wheres_the_car/core/http/http_client.dart';
import 'package:wheres_the_car/core/powersync/local_db.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/data/models/search_models.dart';

/// Fetches ranked/semantic results from the router's `/api/search`. Optional:
/// [SearchRepository.search] merges these in on top of the local PowerSync
/// results, and swallows any failure (offline, timeout, 5xx) so a dead
/// network never blocks a search that the local mirror can already answer.
typedef SearchHttpFetch =
    Future<List<SearchResult>> Function(String query, int limit);

class SearchRepository {
  SearchRepository({LocalDb? localDb, SearchHttpFetch? httpFetch})
    : _localDb = localDb,
      _httpFetch = httpFetch ?? _fetchFromRouter;

  static final SearchRepository instance = SearchRepository();

  // Resolved lazily so tests that never touch the local DB can construct the
  // repository without initializing PowerSync.
  LocalDb? _localDb;
  LocalDb get _db => _localDb ??= PowerSyncService.instance;

  final SearchHttpFetch _httpFetch;

  /// Local-first: static transport data synced via PowerSync (`search_vector`)
  /// answers the query offline. The router call is optional enrichment —
  /// ranked/semantic matches and live entities (bus routes/stations, bike
  /// stations) the local mirror doesn't carry — merged in when it succeeds.
  Future<List<SearchResult>> search(String query, {int limit = 20}) async {
    final local = await _searchLocal(query, limit);
    List<SearchResult> remote;
    try {
      remote = await _httpFetch(query, limit);
    } on Object {
      remote = const [];
    }
    return _merge(local, remote, limit);
  }

  Future<List<SearchResult>> _searchLocal(String query, int limit) async {
    final like = '%$query%';
    final rows = await _db.getAll(
      'SELECT type, uid, name, city, depart, destin '
      'FROM search_vector '
      'WHERE uid = ?1 OR name LIKE ?2 OR depart LIKE ?2 OR destin LIKE ?2 '
      'ORDER BY name LIMIT ?3',
      [query, like, limit],
    );
    final results = <SearchResult>[];
    for (final row in rows) {
      final result = _fromRow(row);
      if (result != null) results.add(result);
    }
    return results;
  }

  static List<SearchResult> _merge(
    List<SearchResult> local,
    List<SearchResult> remote,
    int limit,
  ) {
    final seen = <String>{for (final r in local) '${r.type}:${r.uid}'};
    final merged = [...local];
    for (final r in remote) {
      if (merged.length >= limit) break;
      final key = '${r.type}:${r.uid}';
      if (seen.add(key)) merged.add(r);
    }
    return merged.length > limit ? merged.sublist(0, limit) : merged;
  }

  static SearchResult? _fromRow(Map<String, dynamic> row) {
    final rawType = row['type'] as String? ?? '';
    // Rail stations are no longer search entries — the rail query flow lives
    // on the home sheet, so a station row would have nowhere to navigate.
    if (rawType == 'tra_station' || rawType == 'thsr_station') return null;
    final depart = row['depart'] as String? ?? '';
    final destin = row['destin'] as String? ?? '';
    final city = row['city'] as String?;
    final subtitle = depart.isNotEmpty && destin.isNotEmpty
        ? '$depart → $destin'
        : (city ?? '');
    return SearchResult(
      type: _parseType(rawType),
      uid: row['uid'] as String? ?? '',
      name: row['name'] as String? ?? '',
      subtitle: subtitle,
      city: city,
      lat: (row['lat'] as num?)?.toDouble(),
      lon: (row['lon'] as num?)?.toDouble(),
    );
  }

  static SearchResultType _parseType(String t) => switch (t) {
    'bus_route' => SearchResultType.busRoute,
    'bus_station' => SearchResultType.busStation,
    'bike_station' => SearchResultType.bikeStation,
    'mrt_station' => SearchResultType.mrtStation,
    'tra_train' => SearchResultType.traTrain,
    'thsr_train' => SearchResultType.thsrTrain,
    _ => SearchResultType.busRoute,
  };

  static Future<List<SearchResult>> _fetchFromRouter(
    String query,
    int limit,
  ) async {
    final res = await HttpClient.instance.dio.get<Map<String, dynamic>>(
      '/api/search',
      queryParameters: {'q': query, 'limit': limit},
    );
    final list = (res.data?['results'] as List?) ?? [];
    final results = <SearchResult>[];
    for (final r in list) {
      final result = _fromRow(Map<String, dynamic>.from(r as Map));
      if (result != null) results.add(result);
    }
    return results;
  }
}
