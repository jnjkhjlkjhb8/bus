import 'package:equatable/equatable.dart';

/// Result categories for the live `/api/search` path (SearchBloc/SearchResult).
enum SearchResultType {
  busRoute,
  busStation,
  bikeStation,
  mrtStation,
  traStation,
  thsrStation,
  traTrain,
  thsrTrain,
}

/// A validated search result from the `/api/search` endpoint. Lives in data/
/// so repositories can return it without depending on the search feature.
class SearchResult extends Equatable {
  const SearchResult({
    required this.type,
    required this.uid,
    required this.name,
    required this.subtitle,
    this.city,
    this.lat,
    this.lon,
  });

  final SearchResultType type;
  final String uid;
  final String name;
  final String subtitle;
  final String? city;
  final double? lat;
  final double? lon;

  @override
  List<Object?> get props => [type, uid, name, subtitle, city, lat, lon];
}

/// Search result categories returned by the backend search endpoint.
enum AppSearchResultType {
  busRoute,

  busStation,

  bikeStation,

  mrtStation,

  traStation,

  thsrStation,

  traTrain,

  thsrTrain,

  place,
}

/// Backend-shaped search result data from `/api/search`.
class BackendSearchResult {
  const BackendSearchResult({
    required this.type,
    required this.uid,
    required this.name,
    this.city,
    this.depart = '',
    this.destin = '',
  });

  final AppSearchResultType type;

  /// Stable backend identifier.
  final String uid;

  final String name;

  final String? city;

  final String depart;

  final String destin;
}

/// Presentation data for a search result row.
class SearchResultViewData {
  const SearchResultViewData({
    required this.type,
    required this.uid,
    required this.title,
    required this.subtitle,
  });

  final AppSearchResultType type;

  /// Stable backend identifier.
  final String uid;

  final String title;

  final String subtitle;
}
