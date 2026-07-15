import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract test: every PowerSync table the app declares in
/// `powersync_service.dart` must have a matching bucket data query in
/// `powersync/sync-rules.yaml` — PowerSync names the local SQLite table
/// after the query's `FROM` table, so the names must match exactly — and
/// that query must project every column the app schema declares, under a
/// matching alias, plus a stable `id`.
///
/// This parses the real files on disk (not copies), so it catches drift the
/// moment either side changes. It previously caught: the app declaring six
/// tables (bus_stops, mrt_stations, tra_stations, thsr_stations,
/// mrt_journey_matrix, mrt_schedule) while sync-rules.yaml only populated
/// two (mrt_journey_matrix, mrt_schedule), and search_vector being declared
/// on neither side despite SearchRepository needing it for offline search.
void main() {
  late Map<String, List<String>> appTables;
  late Map<String, _SyncRuleQuery> syncRules;

  setUpAll(() {
    appTables = _parseAppSchema(
      File('lib/core/powersync/powersync_service.dart').readAsStringSync(),
    );
    syncRules = _parseSyncRules(
      File('../powersync/sync-rules.yaml').readAsStringSync(),
    );
  });

  test('app declares at least one PowerSync table', () {
    expect(appTables, isNotEmpty);
  });

  test('sync-rules.yaml declares at least one bucket data query', () {
    expect(syncRules, isNotEmpty);
  });

  test('every app-declared table has a matching sync-rule projection', () {
    final missing = appTables.keys.where((t) => !syncRules.containsKey(t));
    expect(
      missing,
      isEmpty,
      reason:
          'App declares PowerSync table(s) $missing in '
          'powersync_service.dart with no matching `FROM <table>` bucket '
          'data query in powersync/sync-rules.yaml. PowerSync names the '
          "local SQLite table after the query's FROM table, so the "
          'names must match exactly.',
    );
  });

  test('every matching sync-rule query has a stable id column', () {
    for (final table in appTables.keys) {
      final rule = syncRules[table];
      if (rule == null) continue; // reported by the previous test
      expect(
        rule.aliases,
        contains('id'),
        reason: '$table sync-rule query has no `id` alias.',
      );
    }
  });

  test(
    'every matching sync-rule query aliases every app-declared column',
    () {
      final gaps = <String>[];
      for (final entry in appTables.entries) {
        final rule = syncRules[entry.key];
        if (rule == null) continue; // reported by the previous test
        for (final column in entry.value) {
          if (!rule.aliases.contains(column)) {
            gaps.add('${entry.key}.$column');
          }
        }
      }
      expect(
        gaps,
        isEmpty,
        reason:
            'App-declared column(s) $gaps have no matching alias in their '
            "table's sync-rule SELECT list.",
      );
    },
  );
}

/// Parses `Table('name', [Column.xxx('col'), ...])` entries out of the
/// PowerSync schema definition.
Map<String, List<String>> _parseAppSchema(String source) {
  final tables = <String, List<String>>{};
  final tableRe = RegExp(r"Table\('(\w+)',\s*\[([^\]]*)\]\s*\)");
  final columnRe = RegExp(r"Column\.\w+\('(\w+)'\)");
  for (final match in tableRe.allMatches(source)) {
    final name = match.group(1)!;
    final body = match.group(2)!;
    tables[name] = [for (final c in columnRe.allMatches(body)) c.group(1)!];
  }
  return tables;
}

class _SyncRuleQuery {
  _SyncRuleQuery(this.fromTable, this.aliases);

  final String fromTable;
  final Set<String> aliases;
}

/// Parses each `- SELECT ... FROM <table>` bucket data query out of
/// sync-rules.yaml, keyed by the FROM table (the local SQLite table
/// PowerSync will create for it).
Map<String, _SyncRuleQuery> _parseSyncRules(String source) {
  final queries = <String, _SyncRuleQuery>{};
  // Each query starts at "- SELECT" and runs (non-greedily) up to the next
  // "- SELECT" or end of file. None of our queries use parenthesised
  // function calls, so a top-level comma split is enough to separate the
  // select list.
  final queryRe = RegExp(
    r'-\s*SELECT\s+(.*?)\s+FROM\s+(\w+)',
    dotAll: true,
  );
  for (final match in queryRe.allMatches(source)) {
    final selectList = match.group(1)!;
    final fromTable = match.group(2)!;
    final aliases = <String>{};
    for (final rawItem in selectList.split(',')) {
      final item = rawItem.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (item.isEmpty) continue;
      final asMatch = RegExp(
        r'AS\s+(\w+)$',
        caseSensitive: false,
      ).firstMatch(item);
      final alias = asMatch != null ? asMatch.group(1)! : item.split('.').last;
      aliases.add(alias);
    }
    queries[fromTable] = _SyncRuleQuery(fromTable, aliases);
  }
  return queries;
}
