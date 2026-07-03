import 'package:hive_ce_flutter/adapters.dart';

class HiveStore {
  HiveStore._();

  static const _boxLayout = 'board_layout';
  static const _boxFavRoutes = 'fav_routes';
  static const _boxFavorites = 'favorites';
  static const _boxSettings = 'settings';
  static const _boxOnboarded = 'onboarded';
  static const _boxRecents = 'recent_searches';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox<dynamic>(_boxLayout),
      Hive.openBox<dynamic>(_boxFavRoutes),
      Hive.openBox<dynamic>(_boxFavorites),
      Hive.openBox<dynamic>(_boxSettings),
      Hive.openBox<bool>(_boxOnboarded),
      Hive.openBox<dynamic>(_boxRecents),
    ]);
  }

  static Box<dynamic> get layout => Hive.box(_boxLayout);
  static Box<dynamic> get favRoutes => Hive.box(_boxFavRoutes);
  static Box<dynamic> get recents => Hive.box(_boxRecents);

  static List<Map<String, dynamic>> get recentSearches =>
      (recents.get('items', defaultValue: const <dynamic>[]) as List)
          .cast<Map<dynamic, dynamic>>()
          .map((m) => m.cast<String, dynamic>())
          .toList();

  static Future<void> addRecentSearch(Map<String, dynamic> item) async {
    final items = recentSearches
      ..removeWhere(
        (e) => e['uid'] == item['uid'] && e['type'] == item['type'],
      )
      ..insert(0, item);
    await recents.put('items', items.take(10).toList());
  }
  static Box<dynamic> get favorites => Hive.box(_boxFavorites);
  static bool get favoritesReady => Hive.isBoxOpen(_boxFavorites);
  static Box<dynamic> get settings => Hive.box(_boxSettings);
  static bool get settingsReady => Hive.isBoxOpen(_boxSettings);
  static Box<bool> get onboarded => Hive.box<bool>(_boxOnboarded);
  static bool get liveActivityEnabled =>
      settings.get('live_activity_enabled', defaultValue: true) as bool;

  static set liveActivityEnabled(bool v) =>
      settings.put('live_activity_enabled', v);

  static bool get devModeEnabled =>
      settings.get('dev_mode_enabled', defaultValue: false) as bool;

  static set devModeEnabled(bool v) => settings.put('dev_mode_enabled', v);

  static bool get largeText =>
      settings.get('large_text', defaultValue: false) as bool;

  static set largeText(bool v) => settings.put('large_text', v);

  static bool get pushEnabled =>
      settings.get('push_enabled', defaultValue: true) as bool;

  static set pushEnabled(bool value) => settings.put('push_enabled', value);

  static bool get analyticsEnabled =>
      settings.get('analytics_enabled', defaultValue: true) as bool;

  static set analyticsEnabled(bool value) =>
      settings.put('analytics_enabled', value);

  static bool get crashlyticsEnabled =>
      settings.get('crashlytics_enabled', defaultValue: true) as bool;

  static set crashlyticsEnabled(bool value) =>
      settings.put('crashlytics_enabled', value);

  static bool get performanceEnabled =>
      settings.get('performance_enabled', defaultValue: true) as bool;

  static set performanceEnabled(bool value) =>
      settings.put('performance_enabled', value);

  static bool get hasCompletedOnboarding =>
      onboarded.get('done', defaultValue: false)!;

  static Future<void> markOnboardingComplete() => onboarded.put('done', true);

  static List<String> get favMetroStations => List<String>.from(
    settings.get('fav_metro_stations', defaultValue: <String>[]) as List,
  );

  static set favMetroStations(List<String> list) =>
      settings.put('fav_metro_stations', list);
}
