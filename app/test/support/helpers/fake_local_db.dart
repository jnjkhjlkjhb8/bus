import 'package:wheres_the_car/core/powersync/local_db.dart';

/// In-memory [LocalDb] that returns canned rows per query, so repository tests
/// exercise their SQL-to-domain mapping without initializing PowerSync.
///
/// Rows are matched by the first positional parameter (the query's bind value,
/// e.g. a station id or name); an unmatched key yields an empty result.
class FakeLocalDb implements LocalDb {
  FakeLocalDb(this._rowsByKey);

  /// Maps the first query parameter to the rows that query should return.
  final Map<Object?, List<Map<String, dynamic>>> _rowsByKey;

  /// Queries recorded in call order, for assertions.
  final List<({String sql, List<Object?> parameters})> calls = [];

  @override
  Future<List<Map<String, dynamic>>> getAll(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    calls.add((sql: sql, parameters: parameters));
    final key = parameters.isEmpty ? null : parameters.first;
    return _rowsByKey[key] ?? const [];
  }
}
