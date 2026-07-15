import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/data/repositories/settings_repository.dart';

/// Appearance options shown in the settings picker.
///
/// [key] is the value persisted through [SettingsRepository.appearanceMode];
/// [label] is presentation only.
enum Appearance {
  system('跟隨系統', 'system'),
  light('淺色模式', 'light'),
  dark('深色模式', 'dark');

  const Appearance(this.label, this.key);
  final String label;
  final String key;

  static Appearance fromKey(String key) =>
      values.firstWhere((e) => e.key == key, orElse: () => system);
}

/// Language options shown in the settings picker.
///
/// The selection is UI-only state: it is not persisted (mirrors the previous
/// screen behavior, where language reset to [system] on each rebuild).
enum Language {
  system('跟隨系統'),
  zh('繁體中文');

  const Language(this.label);
  final String label;
}

class SettingsState extends Equatable {
  const SettingsState({
    this.appearance = Appearance.system,
    this.language = Language.system,
    this.devMode = false,
    this.versionTaps = 0,
    this.pushEnabled = true,
    this.pushUpdating = false,
    this.analyticsEnabled = true,
    this.crashlyticsEnabled = true,
    this.largeText = false,
    this.liveActivityEnabled = true,
    this.appVersion = '',
    this.powerSyncLastSyncedAt,
  });

  final Appearance appearance;
  final Language language;
  final bool devMode;
  final int versionTaps;
  final bool pushEnabled;
  final bool pushUpdating;
  final bool analyticsEnabled;
  final bool crashlyticsEnabled;
  final bool largeText;
  final bool liveActivityEnabled;

  /// Real running-app version from `PackageInfo`, empty until it loads
  /// (F46). Never hardcoded.
  final String appVersion;

  /// Real PowerSync freshness, null until it loads or before the first sync
  /// completes (F46). Never hardcoded.
  final DateTime? powerSyncLastSyncedAt;

  SettingsState copyWith({
    Appearance? appearance,
    Language? language,
    bool? devMode,
    int? versionTaps,
    bool? pushEnabled,
    bool? pushUpdating,
    bool? analyticsEnabled,
    bool? crashlyticsEnabled,
    bool? largeText,
    bool? liveActivityEnabled,
    String? appVersion,
    DateTime? powerSyncLastSyncedAt,
  }) => SettingsState(
    appearance: appearance ?? this.appearance,
    language: language ?? this.language,
    devMode: devMode ?? this.devMode,
    versionTaps: versionTaps ?? this.versionTaps,
    pushEnabled: pushEnabled ?? this.pushEnabled,
    pushUpdating: pushUpdating ?? this.pushUpdating,
    analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
    crashlyticsEnabled: crashlyticsEnabled ?? this.crashlyticsEnabled,
    largeText: largeText ?? this.largeText,
    liveActivityEnabled: liveActivityEnabled ?? this.liveActivityEnabled,
    appVersion: appVersion ?? this.appVersion,
    powerSyncLastSyncedAt: powerSyncLastSyncedAt ?? this.powerSyncLastSyncedAt,
  );

  @override
  List<Object?> get props => [
    appearance,
    language,
    devMode,
    versionTaps,
    pushEnabled,
    pushUpdating,
    analyticsEnabled,
    crashlyticsEnabled,
    largeText,
    liveActivityEnabled,
    appVersion,
    powerSyncLastSyncedAt,
  ];
}
