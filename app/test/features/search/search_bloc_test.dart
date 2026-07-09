import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/models/search_models.dart';
import 'package:wheres_the_car/data/repositories/search_recent_repository.dart';
import 'package:wheres_the_car/data/repositories/search_repository.dart';
import 'package:wheres_the_car/features/search/bloc/search_bloc.dart';
import 'package:wheres_the_car/features/search/bloc/search_event.dart';

void main() {
  test('loads recents on construction', () async {
    final recent = _FakeSearchRecentRepository(recents: [_result('recent')]);
    final bloc = SearchBloc(
      searchRepository: _FakeSearchRepository(),
      recentRepository: recent,
    );
    addTearDown(bloc.close);

    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.recentResults, hasLength(1));
  });

  test('debounces query changes and searches latest query once', () async {
    final search = _FakeSearchRepository(results: [_result('result')]);
    final bloc = SearchBloc(
      searchRepository: search,
      recentRepository: _FakeSearchRecentRepository(),
    );
    addTearDown(bloc.close);

    bloc
      ..add(const SearchQueryChanged('tai'))
      ..add(const SearchQueryChanged('taipei'));

    await Future<void>.delayed(const Duration(milliseconds: 350));
    await Future<void>.delayed(Duration.zero);

    expect(search.queries, ['taipei']);
    expect(bloc.state.results, hasLength(1));
  });

  test('search errors emit AppError state', () async {
    final bloc = SearchBloc(
      searchRepository: _FakeSearchRepository(error: StateError('offline')),
      recentRepository: _FakeSearchRecentRepository(),
    );
    addTearDown(bloc.close);

    bloc.add(const SearchQueryChanged('taipei'));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.error, isNotNull);
    expect(bloc.state.loading, isFalse);
  });

  test('selected result is added to recents', () async {
    final recent = _FakeSearchRecentRepository();
    final bloc = SearchBloc(
      searchRepository: _FakeSearchRepository(),
      recentRepository: recent,
    );
    addTearDown(bloc.close);

    final result = _result('bus-1');
    bloc.add(SearchResultSelected(result));
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.recentResults, [result]);
  });
}

SearchResult _result(String uid) => SearchResult(
  type: SearchResultType.busRoute,
  uid: uid,
  name: '307',
  subtitle: '板橋',
);

class _FakeSearchRepository implements SearchRepository {
  _FakeSearchRepository({this.results = const [], this.error});

  final List<SearchResult> results;
  final Error? error;
  final List<String> queries = [];

  @override
  Future<List<SearchResult>> search(String query, {int limit = 20}) async {
    queries.add(query);
    final error = this.error;
    if (error != null) throw error;
    return results;
  }
}

class _FakeSearchRecentRepository implements SearchRecentRepository {
  _FakeSearchRecentRepository({List<SearchResult> recents = const []})
    : _recents = [...recents];

  final List<SearchResult> _recents;

  @override
  List<SearchResult> all() => List.unmodifiable(_recents);

  @override
  Future<void> add(SearchResult result) async {
    _recents
      ..removeWhere((r) => r.type == result.type && r.uid == result.uid)
      ..insert(0, result);
  }

  @override
  Future<void> remove(SearchResult result) async {
    _recents.removeWhere((r) => r.type == result.type && r.uid == result.uid);
  }

  @override
  Future<void> clear() async {
    _recents.clear();
  }
}
