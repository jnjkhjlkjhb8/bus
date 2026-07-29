import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:wheres_the_bus/core/firebase/remote_config.dart';
import 'package:wheres_the_bus/data/live/arrival_feed.dart';
import 'package:wheres_the_bus/data/models/alert_models.dart';
import 'package:wheres_the_bus/data/models/subscription_scope.dart';
import 'package:wheres_the_bus/data/repositories/alert_repository.dart';
import 'package:wheres_the_bus/data/repositories/favorites_repository.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_state.dart';

/// Parses the `alert_sources` remote-config value: comma-separated tagged
/// tokens `metro:<system>` and `bus:<city>`. Malformed or unknown-kind tokens
/// are dropped so a bad remote value can't break alert startup. TRA/THSR are
/// nationwide rail and stay wired directly, not listed here.
({List<String> metro, List<String> bus}) parseAlertSources(String csv) {
  final metro = <String>[];
  final bus = <String>[];
  for (final raw in csv.split(',')) {
    final token = raw.trim();
    final sep = token.indexOf(':');
    if (sep <= 0) continue;
    final value = token.substring(sep + 1).trim();
    if (value.isEmpty) continue;
    switch (token.substring(0, sep)) {
      case 'metro':
        metro.add(value);
      case 'bus':
        bus.add(value);
    }
  }
  return (metro: metro, bus: bus);
}

/// Default 訂閱範圍 source: the scope 收藏 currently resolves to, re-emitted
/// whenever 收藏 changes. Injectable via [AlertBloc.new] so tests can drive the
/// filter without Hive.
Stream<Set<String>> _defaultScope() async* {
  final favorites = FavoritesRepository.instance;
  yield subscriptionScope(favorites.all());
  yield* favorites.changes().map((_) => subscriptionScope(favorites.all()));
}

/// Default `alert_sources` config source: emits the current value immediately
/// (so startup doesn't wait for a revision), then re-emits on every
/// activated Remote Config revision. Injectable via [AlertBloc.new] so tests
/// can drive dynamic-subscription behavior (F33) without Firebase.
Stream<String> _defaultAlertSourcesConfig() async* {
  yield AppConfig.getString('alert_sources');
  yield* AppConfig.revisions().map((_) => AppConfig.getString('alert_sources'));
}

/// Ops-authored notices, read from Remote Config. Their text is their
/// identity (same rule as feed alerts), so rewriting an announcement
/// publishes a new one and re-arms its unread state — which is what ops mean
/// when they change the copy.
List<AlertViewModel> readAnnouncements() {
  final maintenance = AppConfig.getString('maintenance_banner_text');
  final announcement = AppConfig.getString('announcement_text');
  return [
    if (AppConfig.getBool('maintenance_banner_enabled') &&
        maintenance.isNotEmpty)
      AlertViewModel(
        message: maintenance,
        level: AlertSeverity.yellow,
        source: const AlertSource(AlertSourceKind.appMaintenance),
      ),
    if (announcement.isNotEmpty)
      AlertViewModel(
        message: announcement,
        level: AlertSeverity.yellow,
        source: const AlertSource(AlertSourceKind.appNotice),
      ),
  ];
}

/// Default 公告 source: the current announcements immediately, then a fresh
/// read on every activated Remote Config revision.
Stream<List<AlertViewModel>> _defaultAnnouncements() async* {
  yield readAnnouncements();
  yield* AppConfig.revisions().map((_) => readAnnouncements());
}

/// Both announcement kinds arrive on one stream, so they share one
/// subscription key; the row's own `source` still says which it is.
const _announcementSource = AlertSourceId(AlertSourceKind.appNotice);

class AlertBloc extends Bloc<AlertEvent, AlertState> {
  AlertBloc({
    AlertRepository? repository,
    Stream<String> Function()? alertSourcesConfig,
    Stream<Set<String>> Function()? scopeSource,
    Stream<List<AlertViewModel>> Function()? announcements,
  }) : _repository = repository ?? AlertRepository.instance,
       _alertSourcesConfig = alertSourcesConfig ?? _defaultAlertSourcesConfig,
       _scopeSource = scopeSource ?? _defaultScope,
       _announcements = announcements ?? _defaultAnnouncements,
       super(
         AlertState(
           readMessages: (repository ?? AlertRepository.instance).readAlerts(),
         ),
       ) {
    on<AlertStarted>(_onStarted);
    on<AlertReceived>(_onReceived);
    on<AlertDismissed>(_onDismissed);
    on<AlertAllDismissed>(_onAllDismissed);
    on<AlertRestored>(_onRestored);
    on<AlertAllRead>(_onAllRead);
    on<AlertMarkedRead>(_onMarkedRead);
    on<AlertStreamFailed>(_onStreamFailed);
    on<AlertStreamRecovered>(_onStreamRecovered);
    on<AlertConfigChanged>(_onConfigChanged);
    on<AlertScopeChanged>(_onScopeChanged);
  }

  final AlertRepository _repository;
  final Stream<String> Function() _alertSourcesConfig;
  final Stream<Set<String>> Function() _scopeSource;
  final Stream<List<AlertViewModel>> Function() _announcements;

  void _persistRead(Set<String> read) {
    unawaited(_repository.persistReadAlerts(read));
  }

  final Map<AlertSourceId, StreamSubscription<List<AlertViewModel>>> _subs = {};
  StreamSubscription<String>? _configSub;
  StreamSubscription<Set<String>>? _scopeSub;
  String? _lastSourcesCsv;

  bool get hasActiveSubscriptions => _subs.isNotEmpty;

  Future<void> _cancelAll() async {
    for (final sub in _subs.values) {
      await sub.cancel();
    }
    _subs.clear();
  }

  void _listenSource(
    AlertSourceId source,
    Stream<List<AlertViewModel>> Function() streamSource,
  ) {
    _subs[source] = ArrivalFeed.passthrough(
      source: streamSource,
      onFailure: (e) => add(AlertStreamFailed(e, source: source)),
      onRecovered: () => add(AlertStreamRecovered(source: source)),
    ).listen((alerts) => add(AlertReceived(source, alerts)));
  }

  Future<void> _onStarted(AlertStarted _, Emitter<AlertState> emit) async {
    await _cancelAll();
    _lastSourcesCsv = null;

    _listenSource(
      const AlertSourceId(AlertSourceKind.tra),
      _repository.traAlert,
    );
    _listenSource(
      const AlertSourceId(AlertSourceKind.thsr),
      _repository.thsrAlert,
    );

    // Subscribed directly rather than through ArrivalFeed: this is a local
    // config read, not a network stream, so there is no failure to surface
    // and nothing to reconnect.
    _subs[_announcementSource] = _announcements().listen(
      (notices) => add(AlertReceived(_announcementSource, notices)),
    );

    await _configSub?.cancel();
    _configSub = _alertSourcesConfig().listen(
      (csv) => add(AlertConfigChanged(csv)),
    );

    await _scopeSub?.cancel();
    _scopeSub = _scopeSource().listen((scope) => add(AlertScopeChanged(scope)));
  }

  /// Diffs the newly-parsed metro/bus sources against what's currently
  /// subscribed and replaces only what changed (F33): kept sources are never
  /// touched (added/removed keys are disjoint from kept ones), so there is no
  /// window where a still-wanted subscription is unsubscribed. An identical
  /// CSV is a no-op — no cancel/resubscribe at all.
  Future<void> _onConfigChanged(
    AlertConfigChanged event,
    Emitter<AlertState> emit,
  ) async {
    if (event.sourcesCsv == _lastSourcesCsv) return;
    _lastSourcesCsv = event.sourcesCsv;

    final parsed = parseAlertSources(event.sourcesCsv);
    // One `bus:<city>` token is two subscriptions: TDX splits advisories and
    // disruptions across separate topics, and both are that city's alerts.
    final desired = <AlertSourceId>{
      for (final system in parsed.metro)
        AlertSourceId(AlertSourceKind.metro, system),
      for (final city in parsed.bus) ...[
        AlertSourceId(AlertSourceKind.busNews, city),
        AlertSourceId(AlertSourceKind.busAlert, city),
      ],
    };
    const configured = {
      AlertSourceKind.metro,
      AlertSourceKind.busNews,
      AlertSourceKind.busAlert,
    };
    final current = _subs.keys
        .where((s) => configured.contains(s.kind))
        .toSet();

    final toRemove = current.difference(desired);
    final toAdd = desired.difference(current);
    if (toRemove.isEmpty && toAdd.isEmpty) return;

    for (final source in toRemove) {
      final sub = _subs.remove(source);
      await sub?.cancel();
    }
    for (final source in toAdd) {
      _listenSource(source, switch (source.kind) {
        AlertSourceKind.metro => () => _repository.metroAlert(source.code),
        AlertSourceKind.busAlert => () => _repository.busAlert(source.code),
        _ => () => _repository.busNews(source.code),
      });
    }

    if (toRemove.isNotEmpty) {
      // A source we intentionally unsubscribed shouldn't keep flagging as
      // failed — drop any stale health entry it left behind.
      final health = {...state.sourceHealth}
        ..removeWhere((key, _) => toRemove.contains(key));
      emit(state.copyWith(sourceHealth: health));
    }
  }

  void _onReceived(AlertReceived event, Emitter<AlertState> emit) {
    // The batch is this source's whole current set, so it replaces that
    // source's entry outright: an alert TDX no longer publishes has been
    // resolved and must stop being shown. Other sources are untouched.
    emit(
      state.copyWith(
        alertsBySource: {...state.alertsBySource, event.source: event.alerts},
      ),
    );
  }

  void _onScopeChanged(AlertScopeChanged event, Emitter<AlertState> emit) {
    if (setEquals(event.scope, state.scope)) return;
    emit(state.copyWith(scope: event.scope));
  }

  void _onDismissed(AlertDismissed event, Emitter<AlertState> emit) {
    emit(
      state.copyWith(
        dismissedMessages: {...state.dismissedMessages, event.message},
      ),
    );
  }

  void _onAllDismissed(AlertAllDismissed event, Emitter<AlertState> emit) {
    emit(
      state.copyWith(
        dismissedMessages: {...state.dismissedMessages, ...event.messages},
      ),
    );
  }

  void _onRestored(AlertRestored event, Emitter<AlertState> emit) {
    final next = {...state.dismissedMessages}..removeAll(event.messages);
    emit(state.copyWith(dismissedMessages: next));
  }

  void _onAllRead(AlertAllRead _, Emitter<AlertState> emit) {
    final read = {
      ...state.readMessages,
      for (final a in state.visibleAlerts) a.message,
    };
    _persistRead(read);
    emit(state.copyWith(readMessages: read));
  }

  void _onMarkedRead(AlertMarkedRead event, Emitter<AlertState> emit) {
    final read = {...state.readMessages, event.message};
    _persistRead(read);
    emit(state.copyWith(readMessages: read));
  }

  void _onStreamFailed(AlertStreamFailed event, Emitter<AlertState> emit) {
    emit(
      state.copyWith(
        sourceHealth: {...state.sourceHealth, event.source: event.error},
      ),
    );
  }

  void _onStreamRecovered(
    AlertStreamRecovered event,
    Emitter<AlertState> emit,
  ) {
    // Only the source that actually failed can clear its own entry — a
    // recovery for an untracked/already-healthy source is a no-op, and other
    // sources' failures stay put (F32).
    if (!state.sourceHealth.containsKey(event.source)) return;
    final health = {...state.sourceHealth}..remove(event.source);
    emit(state.copyWith(sourceHealth: health));
  }

  @override
  Future<void> close() async {
    await _configSub?.cancel();
    _configSub = null;
    await _scopeSub?.cancel();
    _scopeSub = null;
    await _cancelAll();
    return super.close();
  }
}
