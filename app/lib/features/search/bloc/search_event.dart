import 'package:equatable/equatable.dart';
import 'package:wheres_the_bus/data/models/search_models.dart';

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

/// Undo for [SearchRecentRemoved]. Carries the original position so the entry
/// goes back where it was instead of jumping to the head of the list.
class SearchRecentRestored extends SearchEvent {
  const SearchRecentRestored(this.result, this.index);
  final SearchResult result;
  final int index;
  @override
  List<Object?> get props => [result, index];
}

class SearchRecentsCleared extends SearchEvent {
  const SearchRecentsCleared();
}

class SearchQuerySubmitted extends SearchEvent {
  const SearchQuerySubmitted(this.query, this.requestId, {this.city});
  final String query;
  final int requestId;

  /// The city filter this request was issued under, carried on the event
  /// rather than read from the state when it lands: the two can differ once
  /// a chip is tapped mid-flight, and the response has to be attributed to
  /// the filter that produced it.
  final String? city;
  @override
  List<Object?> get props => [query, requestId, city];
}

/// Selects a city, or clears the selection when [city] is already selected.
class SearchCityToggled extends SearchEvent {
  const SearchCityToggled(this.city);
  final String city;
  @override
  List<Object?> get props => [city];
}
