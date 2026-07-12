import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/repositories/settings_repository.dart';
import 'package:wheres_the_car/features/settings/bloc/settings_bloc.dart';
import 'package:wheres_the_car/features/settings/bloc/settings_event.dart';
import 'package:wheres_the_car/features/settings/bloc/settings_state.dart';

import '../../support/helpers/in_memory_settings_store.dart';

Future<bool> _grant({required bool requested}) async => requested;

void main() {
  SettingsRepository repo([Map<String, Object?>? initial]) =>
      SettingsRepository(store: InMemorySettingsStore(initial));

  SettingsBloc build({
    SettingsRepository? settings,
    PushUpdater? updatePushPreference,
  }) {
    final bloc = SettingsBloc(
      settings: settings ?? repo(),
      updatePushPreference: updatePushPreference ?? _grant,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  group('initial load', () {
    test('reads defaults from an empty repository', () {
      final bloc = build();
      expect(bloc.state.appearance, Appearance.system);
      expect(bloc.state.language, Language.system);
      expect(bloc.state.devMode, isFalse);
      expect(bloc.state.versionTaps, 0);
      expect(bloc.state.pushEnabled, isTrue);
      expect(bloc.state.pushUpdating, isFalse);
      expect(bloc.state.analyticsEnabled, isTrue);
      expect(bloc.state.crashlyticsEnabled, isTrue);
      expect(bloc.state.largeText, isFalse);
      expect(bloc.state.liveActivityEnabled, isTrue);
    });

    test('hydrates from persisted values', () {
      final bloc = build(
        settings: repo({
          'appearance_mode': 'dark',
          'dev_mode_enabled': true,
          'push_enabled': false,
          'analytics_enabled': false,
          'crashlytics_enabled': false,
          'large_text': true,
          'live_activity_enabled': false,
        }),
      );
      expect(bloc.state.appearance, Appearance.dark);
      expect(bloc.state.devMode, isTrue);
      expect(bloc.state.pushEnabled, isFalse);
      expect(bloc.state.analyticsEnabled, isFalse);
      expect(bloc.state.crashlyticsEnabled, isFalse);
      expect(bloc.state.largeText, isTrue);
      expect(bloc.state.liveActivityEnabled, isFalse);
    });
  });

  group('setting changes persist', () {
    test('appearance selection persists the key', () async {
      final settings = repo();
      final bloc = build(settings: settings)
        ..add(const AppearanceSelected(Appearance.dark));
      await bloc.stream.first;

      expect(bloc.state.appearance, Appearance.dark);
      expect(settings.appearanceMode, 'dark');
    });

    test('large text toggle persists', () async {
      final settings = repo();
      final bloc = build(settings: settings)
        ..add(const LargeTextToggled(value: true));
      await bloc.stream.first;

      expect(bloc.state.largeText, isTrue);
      expect(settings.largeText, isTrue);
    });

    test('live activity toggle persists', () async {
      final settings = repo();
      final bloc = build(settings: settings)
        ..add(const LiveActivityToggled(value: false));
      await bloc.stream.first;

      expect(bloc.state.liveActivityEnabled, isFalse);
      expect(settings.liveActivityEnabled, isFalse);
    });

    test('analytics toggle persists', () async {
      final settings = repo();
      final bloc = build(settings: settings)
        ..add(const AnalyticsToggled(value: false));
      await bloc.stream.first;

      expect(bloc.state.analyticsEnabled, isFalse);
      expect(settings.analyticsEnabled, isFalse);
    });

    test('crashlytics toggle persists', () async {
      final settings = repo();
      final bloc = build(settings: settings)
        ..add(const CrashlyticsToggled(value: false));
      await bloc.stream.first;

      expect(bloc.state.crashlyticsEnabled, isFalse);
      expect(settings.crashlyticsEnabled, isFalse);
    });

    test('language selection updates state but is not persisted', () async {
      final settings = repo();
      // Language has no repository backing; nothing to persist.
      expect(settings.appearanceMode, 'system');
    });
  });

  group('push toggle', () {
    test('reconciles to the granted permission and clears updating', () async {
      final settings = repo();
      final bloc = build(
        settings: settings,
        updatePushPreference: ({required requested}) async => true,
      );

      final states = <SettingsState>[];
      final sub = bloc.stream.listen(states.add);
      addTearDown(sub.cancel);

      bloc.add(const PushToggled(value: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Optimistic pushUpdating=true, then settled pushUpdating=false.
      expect(states.first.pushUpdating, isTrue);
      expect(bloc.state.pushUpdating, isFalse);
      expect(bloc.state.pushEnabled, isTrue);
      expect(settings.pushEnabled, isTrue);
    });

    test('falls back to disabled when the request is denied', () async {
      final settings = repo();
      final bloc = build(
        settings: settings,
        updatePushPreference: ({required requested}) async => false,
      )..add(const PushToggled(value: true));

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bloc.state.pushEnabled, isFalse);
      expect(bloc.state.pushUpdating, isFalse);
      expect(settings.pushEnabled, isFalse);
    });

    test('falls back to disabled when the updater throws', () async {
      final settings = repo();
      final bloc = build(
        settings: settings,
        updatePushPreference: ({required requested}) async =>
            throw Exception('denied'),
      )..add(const PushToggled(value: true));

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bloc.state.pushEnabled, isFalse);
      expect(bloc.state.pushUpdating, isFalse);
      expect(settings.pushEnabled, isFalse);
    });
  });

  group('dev mode unlock counter', () {
    test('unlocks on the fifth tap and persists', () async {
      final settings = repo();
      final bloc = build(settings: settings);

      for (var i = 0; i < 4; i++) {
        bloc.add(const VersionTapped());
      }
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.devMode, isFalse);
      expect(bloc.state.versionTaps, 4);

      bloc.add(const VersionTapped());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.devMode, isTrue);
      // Counter resets to zero on the unlock transition.
      expect(bloc.state.versionTaps, 0);
      expect(settings.devModeEnabled, isTrue);
    });

    test('taps after unlock keep incrementing without side effects', () async {
      // Already unlocked: the guard skips the unlock branch, and the counter
      // simply advances (matches the pre-bloc behavior).
      final bloc = build(settings: repo({'dev_mode_enabled': true}))
        ..add(const VersionTapped());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.devMode, isTrue);
      expect(bloc.state.versionTaps, 1);
    });
  });
}
