import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';

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

class SearchState extends Equatable {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.loading = false,
    this.error,
    this.recentResults = const [],
  });

  final String query;
  final List<SearchResult> results;
  final bool loading;
  final AppError? error;
  final List<SearchResult> recentResults;

  SearchState copyWith({
    String? query,
    List<SearchResult>? results,
    bool? loading,
    AppError? error,
    bool clearError = false,
    List<SearchResult>? recentResults,
  }) => SearchState(
    query: query ?? this.query,
    results: results ?? this.results,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    recentResults: recentResults ?? this.recentResults,
  );

  @override
  List<Object?> get props => [query, results, loading, error, recentResults];
}
