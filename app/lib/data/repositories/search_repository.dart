import 'package:wheres_the_car/core/http/http_client.dart';
import 'package:wheres_the_car/data/models/search_models.dart';

class SearchRepository {
  const SearchRepository._();
  static const instance = SearchRepository._();

  Future<List<SearchResult>> search(String query, {int limit = 20}) async {
    final res = await HttpClient.instance.dio.get<Map<String, dynamic>>(
      '/api/search',
      queryParameters: {'q': query, 'limit': limit},
    );
    final list = (res.data?['results'] as List?) ?? [];
    return list.map((r) {
      final row = Map<String, dynamic>.from(r as Map);
      final type = _parseType(row['type'] as String? ?? '');
      final depart = row['depart'] as String? ?? '';
      final destin = row['destin'] as String? ?? '';
      final subtitle = depart.isNotEmpty && destin.isNotEmpty
          ? '$depart → $destin'
          : (row['city'] as String? ?? '');
      return SearchResult(
        type: type,
        uid: row['uid'] as String? ?? '',
        name: row['name'] as String? ?? '',
        subtitle: subtitle,
        city: row['city'] as String?,
        lat: (row['lat'] as num?)?.toDouble(),
        lon: (row['lon'] as num?)?.toDouble(),
      );
    }).toList();
  }

  static SearchResultType _parseType(String t) => switch (t) {
    'bus_route' => SearchResultType.busRoute,
    'bus_station' => SearchResultType.busStation,
    'bike_station' => SearchResultType.bikeStation,
    'mrt_station' => SearchResultType.mrtStation,
    'tra_station' => SearchResultType.traStation,
    'thsr_station' => SearchResultType.thsrStation,
    'tra_train' => SearchResultType.traTrain,
    'thsr_train' => SearchResultType.thsrTrain,
    _ => SearchResultType.busRoute,
  };
}
