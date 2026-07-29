import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/data/models/city_names.dart';
import 'package:wheres_the_bus/data/models/search_models.dart';
import 'package:wheres_the_bus/data/repositories/search_recent_repository.dart';
import 'package:wheres_the_bus/data/repositories/search_repository.dart';
import 'package:wheres_the_bus/features/search/bloc/search_event.dart';
import 'package:wheres_the_bus/features/search/bloc/search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc({
    SearchRepository? searchRepository,
    SearchRecentRepository recentRepository = SearchRecentRepository.instance,
  }) : _searchRepository = searchRepository ?? SearchRepository.instance,
       _recentRepository = recentRepository,
       super(const SearchState()) {
    on<SearchQueryChanged>(_onQueryChanged);
    on<SearchQuerySubmitted>(_onQuerySubmitted);
    on<SearchCityToggled>(_onCityToggled);
    on<SearchCleared>(_onCleared);
    on<SearchRecentRequested>(_onRecentRequested);
    on<SearchRecentRemoved>(_onRecentRemoved);
    on<SearchRecentRestored>(_onRecentRestored);
    on<SearchRecentsCleared>(_onRecentsCleared);
    on<SearchResultSelected>(_onResultSelected);
    add(const SearchRecentRequested());
  }

  /// Long enough that a steady typist doesn't fire a request per keystroke,
  /// short enough that the wait isn't what the user is feeling. Every
  /// in-flight request is superseded by id, so the floor here is about
  /// request volume, not correctness.
  static const _debounceDelay = Duration(milliseconds: 180);

  final SearchRepository _searchRepository;
  final SearchRecentRepository _recentRepository;
  Timer? _debounce;
  int _requestId = 0;

  void _onQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) {
    final q = event.query.trim();
    final requestId = ++_requestId;
    emit(state.copyWith(query: q, clearError: true));

    _debounce?.cancel();
    if (q.isEmpty) {
      // An empty query shows recents, where the chip row isn't rendered — a
      // filter kept here would be state the user can't see or undo.
      emit(
        state.copyWith(
          results: [],
          loading: false,
          clearCity: true,
          cityOptions: const [],
        ),
      );
      return;
    }

    emit(state.copyWith(loading: true));
    final city = state.city;
    _debounce = Timer(_debounceDelay, () {
      if (!isClosed) add(SearchQuerySubmitted(q, requestId, city: city));
    });
  }

  /// Re-queries under the new filter instead of narrowing the results in
  /// place: the response is capped, so the rows already on screen are only
  /// that city's share of the top of the list, not its rows.
  void _onCityToggled(SearchCityToggled event, Emitter<SearchState> emit) {
    if (state.query.isEmpty) return;
    final city = state.city == event.city ? null : event.city;
    final requestId = ++_requestId;
    _debounce?.cancel();
    emit(
      state.copyWith(
        city: city,
        clearCity: city == null,
        loading: true,
        clearError: true,
      ),
    );
    // No debounce: a tap is a decision, not a keystroke on the way to one.
    add(SearchQuerySubmitted(state.query, requestId, city: city));
  }

  Future<void> _onQuerySubmitted(
    SearchQuerySubmitted event,
    Emitter<SearchState> emit,
  ) async {
    if (event.requestId != _requestId || event.query != state.query) return;
    try {
      final results = await _searchRepository.search(
        event.query,
        city: event.city,
      );
      if (event.requestId == _requestId && !isClosed) {
        emit(
          state.copyWith(
            results: results,
            loading: false,
            clearError: true,
            cityOptions: event.city == null ? _cityOptions(results) : null,
          ),
        );
      }
    } on Object catch (e) {
      if (event.requestId == _requestId && !isClosed) {
        emit(
          state.copyWith(
            results: const [],
            loading: false,
            error: AppError.from(e),
          ),
        );
      }
    }
  }

  /// City codes present in [results], most-represented first so the likeliest
  /// target sits nearest the start of the row; ties break north to south.
  ///
  /// derived from the page the router returned, so a city with no row in the
  /// top results gets no chip. The row's job is naming what the current
  /// results are mixing together, not listing every city in Taiwan — that
  /// would be a second aggregate query on every keystroke.
  static List<String> _cityOptions(List<SearchResult> results) {
    final counts = <String, int>{};
    for (final r in results) {
      final city = r.city;
      if (city == null || city.isEmpty) continue;
      counts[city] = (counts[city] ?? 0) + 1;
    }
    final codes = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : cityOrder(a).compareTo(cityOrder(b));
      });
    return codes;
  }

  void _onCleared(SearchCleared _, Emitter<SearchState> emit) {
    _debounce?.cancel();
    _requestId++;
    emit(
      SearchState(
        recentResults: state.recentResults,
      ),
    );
  }

  void _onRecentRequested(
    SearchRecentRequested _,
    Emitter<SearchState> emit,
  ) {
    emit(state.copyWith(recentResults: _recentRepository.all()));
  }

  Future<void> _onRecentRemoved(
    SearchRecentRemoved event,
    Emitter<SearchState> emit,
  ) async {
    await _recentRepository.remove(event.result);
    emit(state.copyWith(recentResults: _recentRepository.all()));
  }

  Future<void> _onRecentRestored(
    SearchRecentRestored event,
    Emitter<SearchState> emit,
  ) async {
    await _recentRepository.restore(event.result, event.index);
    emit(state.copyWith(recentResults: _recentRepository.all()));
  }

  Future<void> _onRecentsCleared(
    SearchRecentsCleared _,
    Emitter<SearchState> emit,
  ) async {
    await _recentRepository.clear();
    emit(state.copyWith(recentResults: const []));
  }

  Future<void> _onResultSelected(
    SearchResultSelected event,
    Emitter<SearchState> emit,
  ) async {
    await _recentRepository.add(event.result);
    emit(state.copyWith(recentResults: _recentRepository.all()));
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
