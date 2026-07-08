import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_car/core/http/http_client.dart';
import 'package:wheres_the_car/features/go/model/planned_place.dart';

/// One autocomplete row: a place id plus display text, no coordinates yet.
/// Coordinates come from [PlacesRepository.details] on selection.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;
}

/// Google Places API (New): Autocomplete for type-ahead, Place Details to
/// resolve the chosen suggestion to a coordinate. Both calls share a session
/// token so Google bills them as one session.
class PlacesRepository {
  PlacesRepository._();
  static final PlacesRepository instance = PlacesRepository._();

  static const _apiKey = String.fromEnvironment('GOOGLE_PLACES_API_KEY');
  static const _autocompleteUrl =
      'https://places.googleapis.com/v1/places:autocomplete';
  static const _detailsBase = 'https://places.googleapis.com/v1/places/';

  Dio get _dio => HttpClient.instance.dio;

  /// Empty result when no key is configured (e.g. test env) so the UI degrades
  /// to just the current-location option instead of erroring.
  bool get _enabled => _apiKey.isNotEmpty;

  Future<List<PlaceSuggestion>> autocomplete(
    String query,
    String sessionToken,
  ) async {
    if (!_enabled || query.isEmpty) return const [];
    final res = await _dio.post<Map<String, dynamic>>(
      _autocompleteUrl,
      data: {
        'input': query,
        'sessionToken': sessionToken,
        'languageCode': 'zh-TW',
        'regionCode': 'TW',
        'includedRegionCodes': ['tw'],
      },
      options: Options(headers: {'X-Goog-Api-Key': _apiKey}),
    );
    return parseSuggestions(res.data ?? const {});
  }

  Future<PlannedPlace> details(String placeId, String sessionToken) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '$_detailsBase$placeId',
      queryParameters: {'sessionToken': sessionToken},
      options: Options(
        headers: {
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'location,displayName',
        },
      ),
    );
    return parseDetails(res.data ?? const {});
  }

  /// Pure parser (unit-tested): Places Autocomplete (New) response -> rows.
  /// Skips query predictions that have no place id (e.g. category guesses).
  static List<PlaceSuggestion> parseSuggestions(Map<String, dynamic> json) {
    final suggestions = json['suggestions'];
    if (suggestions is! List) return const [];
    final out = <PlaceSuggestion>[];
    for (final s in suggestions) {
      final pred = (s as Map)['placePrediction'];
      if (pred is! Map) continue;
      final placeId = pred['placeId'] as String?;
      if (placeId == null || placeId.isEmpty) continue;
      final fmt = pred['structuredFormat'] as Map?;
      final primary =
          (fmt?['mainText'] as Map?)?['text'] as String? ??
          (pred['text'] as Map?)?['text'] as String? ??
          '';
      final secondary = (fmt?['secondaryText'] as Map?)?['text'] as String?;
      out.add(
        PlaceSuggestion(
          placeId: placeId,
          primaryText: primary,
          secondaryText: secondary ?? '',
        ),
      );
    }
    return out;
  }

  /// Pure parser (unit-tested): Places Details (New) response -> a place.
  static PlannedPlace parseDetails(Map<String, dynamic> json) {
    final loc = json['location'] as Map?;
    final lat = (loc?['latitude'] as num?)?.toDouble();
    final lon = (loc?['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) {
      throw const FormatException('Place details missing location');
    }
    final name = (json['displayName'] as Map?)?['text'] as String? ?? '地點';
    return PlannedPlace(name: name, latLng: LatLng(lat, lon));
  }
}
