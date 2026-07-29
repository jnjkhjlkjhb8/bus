import 'package:equatable/equatable.dart';
import 'package:wheres_the_bus/data/models/fare_type.dart';
import 'package:wheres_the_bus/features/settings/bloc/settings_state.dart';

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

class LiveActivityToggled extends SettingsEvent {
  const LiveActivityToggled({required this.value});

  final bool value;

  @override
  List<Object?> get props => [value];
}

class ShakeToReportToggled extends SettingsEvent {
  const ShakeToReportToggled({required this.value});

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

/// The rider picked a ticket type in 設定 › 票價. Applies to every fare the
/// app quotes — bus, TRA and THSR.
class FareTypeSelected extends SettingsEvent {
  const FareTypeSelected(this.fareType);

  final FareType fareType;

  @override
  List<Object?> get props => [fareType];
}

/// The rider tapped 檢查更新. Pulls a fresh Remote Config revision and
/// re-resolves the running build against it.
class UpdateCheckRequested extends SettingsEvent {
  const UpdateCheckRequested();
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
