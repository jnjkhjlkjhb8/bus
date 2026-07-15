import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/firebase/firebase_bootstrap.dart';
import 'package:wheres_the_car/core/firebase/firebase_gate.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/data/repositories/settings_repository.dart';
import 'package:wheres_the_car/features/settings/bloc/settings_event.dart';
import 'package:wheres_the_car/features/settings/bloc/settings_state.dart';

/// Applies the requested push preference and returns the effective state.
typedef PushUpdater = Future<bool> Function({required bool requested});

/// Number of version-row taps that unlocks developer mode.
const _devModeTapThreshold = 5;

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({
    SettingsRepository? settings,
    PushUpdater? updatePushPreference,
    Future<PackageInfo> Function()? packageInfoLoader,
    DateTime? Function()? lastSyncedAtOf,
  }) : this._(
         settings ?? SettingsRepository.instance,
         updatePushPreference ?? FirebaseBootstrap.updatePushPreference,
         packageInfoLoader ?? PackageInfo.fromPlatform,
         lastSyncedAtOf ?? (() => PowerSyncService.instance.lastSyncedAt),
       );

  SettingsBloc._(
    this._settings,
    this._updatePush,
    this._packageInfoLoader,
    this._lastSyncedAtOf,
  ) : super(_initialState(_settings)) {
    on<AppearanceSelected>(_onAppearanceSelected);
    on<LanguageSelected>(_onLanguageSelected);
    on<LargeTextToggled>(_onLargeTextToggled);
    on<LiveActivityToggled>(_onLiveActivityToggled);
    on<PushToggled>(_onPushToggled);
    on<AnalyticsToggled>(_onAnalyticsToggled);
    on<CrashlyticsToggled>(_onCrashlyticsToggled);
    on<VersionTapped>(_onVersionTapped);
    on<AppMetadataLoaded>(_onAppMetadataLoaded);
    unawaited(_loadMetadata());
  }

  final SettingsRepository _settings;
  final PushUpdater _updatePush;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final DateTime? Function() _lastSyncedAtOf;

  /// Reads the real app version and PowerSync freshness (F46) and emits them
  /// once both are known. Each loader is guarded independently so, e.g., a
  /// `PackageInfo` platform-channel failure doesn't also blank out a freshly
  /// read sync timestamp.
  Future<void> _loadMetadata() async {
    var version = '';
    try {
      version = (await _packageInfoLoader()).version;
    } on Object catch (_) {
      // Leave the row blank rather than showing a stale/fake version.
    }
    DateTime? lastSyncedAt;
    try {
      lastSyncedAt = _lastSyncedAtOf();
    } on Object catch (_) {
      // PowerSync not initialized yet, or unavailable in this test/build.
    }
    if (!isClosed) {
      add(
        AppMetadataLoaded(
          appVersion: version,
          powerSyncLastSyncedAt: lastSyncedAt,
        ),
      );
    }
  }

  void _onAppMetadataLoaded(
    AppMetadataLoaded e,
    Emitter<SettingsState> emit,
  ) {
    emit(
      state.copyWith(
        appVersion: e.appVersion,
        powerSyncLastSyncedAt: e.powerSyncLastSyncedAt,
      ),
    );
  }

  static SettingsState _initialState(SettingsRepository s) => SettingsState(
    appearance: Appearance.fromKey(s.appearanceMode),
    devMode: s.devModeEnabled,
    pushEnabled: s.pushEnabled,
    analyticsEnabled: s.analyticsEnabled,
    crashlyticsEnabled: s.crashlyticsEnabled,
    largeText: s.largeText,
    liveActivityEnabled: s.liveActivityEnabled,
  );

  void _onAppearanceSelected(
    AppearanceSelected e,
    Emitter<SettingsState> emit,
  ) {
    _settings.appearanceMode = e.appearance.key;
    emit(state.copyWith(appearance: e.appearance));
  }

  // Language is UI-only state; it is not persisted.
  void _onLanguageSelected(LanguageSelected e, Emitter<SettingsState> emit) {
    emit(state.copyWith(language: e.language));
  }

  void _onLargeTextToggled(LargeTextToggled e, Emitter<SettingsState> emit) {
    _settings.largeText = e.value;
    emit(state.copyWith(largeText: e.value));
  }

  void _onLiveActivityToggled(
    LiveActivityToggled e,
    Emitter<SettingsState> emit,
  ) {
    _settings.liveActivityEnabled = e.value;
    emit(state.copyWith(liveActivityEnabled: e.value));
  }

  Future<void> _onPushToggled(
    PushToggled e,
    Emitter<SettingsState> emit,
  ) async {
    if (state.pushUpdating) return;
    // Persist optimistically, then reconcile with the platform's effective
    // permission once the async request settles.
    _settings.pushEnabled = e.value;
    emit(state.copyWith(pushEnabled: e.value, pushUpdating: true));
    var enabled = false;
    try {
      enabled = await _updatePush(requested: e.value);
    } on Object catch (_) {
      enabled = false;
    } finally {
      _settings.pushEnabled = enabled;
      if (!isClosed) {
        emit(state.copyWith(pushEnabled: enabled, pushUpdating: false));
      }
    }
  }

  Future<void> _onAnalyticsToggled(
    AnalyticsToggled e,
    Emitter<SettingsState> emit,
  ) async {
    _settings.analyticsEnabled = e.value;
    emit(state.copyWith(analyticsEnabled: e.value));
    if (!FirebaseGate.enabled) return;
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(e.value);
    } on Object catch (err, s) {
      CrashReporter.record(err, s);
    }
  }

  Future<void> _onCrashlyticsToggled(
    CrashlyticsToggled e,
    Emitter<SettingsState> emit,
  ) async {
    _settings.crashlyticsEnabled = e.value;
    emit(state.copyWith(crashlyticsEnabled: e.value));
    if (!FirebaseGate.enabled) return;
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        e.value,
      );
    } on Object catch (err, s) {
      CrashReporter.record(err, s);
    }
  }

  void _onVersionTapped(VersionTapped e, Emitter<SettingsState> emit) {
    final taps = state.versionTaps + 1;
    if (taps >= _devModeTapThreshold && !state.devMode) {
      _settings.devModeEnabled = true;
      emit(state.copyWith(devMode: true, versionTaps: 0));
      return;
    }
    emit(state.copyWith(versionTaps: taps));
  }
}
