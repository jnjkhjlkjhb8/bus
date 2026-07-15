import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/features/settings/bloc/settings_state.dart';

sealed class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class AppearanceSelected extends SettingsEvent {
  const AppearanceSelected(this.appearance);

  final Appearance appearance;

  @override
  List<Object?> get props => [appearance];
}

class LanguageSelected extends SettingsEvent {
  const LanguageSelected(this.language);

  final Language language;

  @override
  List<Object?> get props => [language];
}

class LargeTextToggled extends SettingsEvent {
  const LargeTextToggled({required this.value});

  final bool value;

  @override
  List<Object?> get props => [value];
}

class LiveActivityToggled extends SettingsEvent {
  const LiveActivityToggled({required this.value});

  final bool value;

  @override
  List<Object?> get props => [value];
}

class PushToggled extends SettingsEvent {
  const PushToggled({required this.value});

  final bool value;

  @override
  List<Object?> get props => [value];
}

class AnalyticsToggled extends SettingsEvent {
  const AnalyticsToggled({required this.value});

  final bool value;

  @override
  List<Object?> get props => [value];
}

class CrashlyticsToggled extends SettingsEvent {
  const CrashlyticsToggled({required this.value});

  final bool value;

  @override
  List<Object?> get props => [value];
}

class VersionTapped extends SettingsEvent {
  const VersionTapped();
}

/// Carries the real app version and PowerSync freshness once both loaders
/// settle (F46). Fired once from the bloc constructor; never dispatched by
/// the UI.
class AppMetadataLoaded extends SettingsEvent {
  const AppMetadataLoaded({
    required this.appVersion,
    required this.powerSyncLastSyncedAt,
  });

  final String appVersion;
  final DateTime? powerSyncLastSyncedAt;

  @override
  List<Object?> get props => [appVersion, powerSyncLastSyncedAt];
}
