import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/data/models/search_models.dart';

sealed class SearchEvent extends Equatable {
  const SearchEvent();
  @override
  List<Object?> get props => [];
}

class SearchQueryChanged extends SearchEvent {
  const SearchQueryChanged(this.query);
  final String query;
  @override
  List<Object?> get props => [query];
}

class SearchCleared extends SearchEvent {
  const SearchCleared();
}

class SearchResultSelected extends SearchEvent {
  const SearchResultSelected(this.result);
  final SearchResult result;
  @override
  List<Object?> get props => [result];
}

class SearchRecentRequested extends SearchEvent {
  const SearchRecentRequested();
}

class SearchRecentRemoved extends SearchEvent {
  const SearchRecentRemoved(this.result);
  final SearchResult result;
  @override
  List<Object?> get props => [result];
}

class SearchQuerySubmitted extends SearchEvent {
  const SearchQuerySubmitted(this.query, this.requestId);
  final String query;
  final int requestId;
  @override
  List<Object?> get props => [query, requestId];
}
