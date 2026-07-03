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
