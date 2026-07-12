import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/repositories/settings_repository.dart';

import '../../support/helpers/in_memory_settings_store.dart';

void main() {
  SettingsRepository build([Map<String, Object?>? initial]) =>
      SettingsRepository(store: InMemorySettingsStore(initial));

  test('bool settings default to their documented values', () {
    final repo = build();
    expect(repo.liveActivityEnabled, isTrue);
    expect(repo.pushEnabled, isTrue);
    expect(repo.analyticsEnabled, isTrue);
    expect(repo.crashlyticsEnabled, isTrue);
    expect(repo.performanceEnabled, isTrue);
    expect(repo.devModeEnabled, isFalse);
    expect(repo.largeText, isFalse);
  });

  test('bool settings round-trip through the store', () {
    final repo = build()
      ..liveActivityEnabled = false
      ..devModeEnabled = true
      ..largeText = true;
    expect(repo.liveActivityEnabled, isFalse);
    expect(repo.devModeEnabled, isTrue);
    expect(repo.largeText, isTrue);
  });

  test('favMetroStations round-trips a list', () {
    final repo = build();
    expect(repo.favMetroStations, isEmpty);
    repo.favMetroStations = ['BL01', 'R02'];
    expect(repo.favMetroStations, ['BL01', 'R02']);
  });

  test('read alerts round-trip and start empty', () async {
    final repo = build();
    expect(repo.readAlerts(), isEmpty);
    await repo.setReadAlerts({'a', 'b'});
    expect(repo.readAlerts(), {'a', 'b'});
  });
}
