import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:wheres_the_bus/core/storage/hive_store.dart';

/// Guards the two sweep rules in [HiveStore.pruneStaticCache] (ADR-0017).
/// Both fail silently in production if they are wrong — a too-greedy key match
/// just looks like "the offline cache never works", which is the hardest
/// possible symptom to trace back to here.
void main() {
  setUp(() async {
    Hive.init('./.dart_tool/hive_test_static_cache');
    await Hive.openBox<dynamic>('static_cache');
    await HiveStore.staticCache.clear();
  });

  tearDown(() async => Hive.box<dynamic>('static_cache').close());

  Future<void> prune({required String build, required DateTime now}) =>
      HiveStore.pruneStaticCache(now: now, buildNumber: () async => build);

  test('a build-number change truncates the whole box', () async {
    await HiveStore.putStatic('s:bus:group:G1', const [1, 2, 3]);
    await prune(build: '41', now: DateTime(2026, 7, 28));
    // First run only stamps the epoch; the entry predates it and goes.
    expect(HiveStore.getStatic('s:bus:group:G1'), isNull);

    await HiveStore.putStatic('s:bus:group:G1', const [1, 2, 3]);
    await prune(build: '41', now: DateTime(2026, 7, 28));
    expect(HiveStore.getStatic('s:bus:group:G1'), const [1, 2, 3]);

    await prune(build: '42', now: DateTime(2026, 7, 28));
    expect(HiveStore.getStatic('s:bus:group:G1'), isNull);
  });

  test('past service dates are swept, today and future are kept', () async {
    await prune(build: '42', now: DateTime(2026, 7, 28));

    await HiveStore.putStatic('s:tra:fare:1000:1040', const [1]);
    await HiveStore.putStatic('d:2026-07-27:tra:tt:1000:1040', const [2]);
    await HiveStore.putStatic('d:2026-07-28:tra:tt:1000:1040', const [3]);
    // A rider can look up a trip days ahead; that entry has to survive every
    // launch between booking-time and travel-day.
    await HiveStore.putStatic('d:2026-08-05:tra:tt:1000:1040', const [4]);

    await prune(build: '42', now: DateTime(2026, 7, 28));

    expect(HiveStore.getStatic('s:tra:fare:1000:1040'), const [1]);
    expect(HiveStore.getStatic('d:2026-07-27:tra:tt:1000:1040'), isNull);
    expect(HiveStore.getStatic('d:2026-07-28:tra:tt:1000:1040'), const [3]);
    expect(HiveStore.getStatic('d:2026-08-05:tra:tt:1000:1040'), const [4]);
  });

  test('dateStamp zero-pads so keys compare lexicographically', () {
    expect(HiveStore.dateStamp(DateTime(2026, 8, 5)), '2026-08-05');
    expect(
      HiveStore.dateStamp(DateTime(2026, 8, 5)).compareTo('2026-08-12') < 0,
      isTrue,
    );
  });
}
