import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/repositories/search_recent_repository.dart';
import 'package:wheres_the_car/data/repositories/search_repository.dart';
import 'package:wheres_the_car/features/search/bloc/search_event.dart';
import 'package:wheres_the_car/features/search/bloc/search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc({
    SearchRepository searchRepository = SearchRepository.instance,
    SearchRecentRepository recentRepository = SearchRecentRepository.instance,
  }) : _searchRepository = searchRepository,
       _recentRepository = recentRepository,
       super(const SearchState()) {
    on<SearchQueryChanged>(_onQueryChanged);
    on<SearchQuerySubmitted>(_onQuerySubmitted);
    on<SearchCleared>(_onCleared);
    on<SearchRecentRequested>(_onRecentRequested);
    on<SearchResultSelected>(_onResultSelected);
    add(const SearchRecentRequested());
  }

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
      emit(state.copyWith(results: [], loading: false));
      return;
    }

    emit(state.copyWith(loading: true));
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!isClosed) add(SearchQuerySubmitted(q, requestId));
    });
  }

  Future<void> _onQuerySubmitted(
    SearchQuerySubmitted event,
    Emitter<SearchState> emit,
  ) async {
    if (event.requestId != _requestId || event.query != state.query) return;
    try {
      final results = await _searchRepository.search(event.query);
      if (event.requestId == _requestId && !isClosed) {
        emit(
          state.copyWith(results: results, loading: false, clearError: true),
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
