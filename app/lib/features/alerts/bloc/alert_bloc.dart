import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:wheres_the_car/core/firebase/remote_config.dart';
import 'package:wheres_the_car/data/live/arrival_feed.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';
import 'package:wheres_the_car/data/repositories/alert_repository.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_state.dart';

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

/// Default `alert_sources` config source: emits the current value immediately
/// (so startup doesn't wait for a revision), then re-emits on every
/// activated Remote Config revision. Injectable via [AlertBloc.new] so tests
/// can drive dynamic-subscription behavior (F33) without Firebase.
Stream<String> _defaultAlertSourcesConfig() async* {
  yield AppConfig.getString('alert_sources');
  yield* AppConfig.revisions().map((_) => AppConfig.getString('alert_sources'));
}

class AlertBloc extends Bloc<AlertEvent, AlertState> {
  AlertBloc({
    AlertRepository? repository,
    Stream<String> Function()? alertSourcesConfig,
  }) : _repository = repository ?? AlertRepository.instance,
       _alertSourcesConfig = alertSourcesConfig ?? _defaultAlertSourcesConfig,
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
  }

  final AlertRepository _repository;
  final Stream<String> Function() _alertSourcesConfig;

  void _persistRead(Set<String> read) {
    unawaited(_repository.persistReadAlerts(read));
  }

  final Map<AlertSourceId, StreamSubscription<AlertViewModel>> _subs = {};
  StreamSubscription<String>? _configSub;
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
    Stream<AlertViewModel> Function() streamSource,
  ) {
    _subs[source] = ArrivalFeed.passthrough(
      source: streamSource,
      onFailure: (e) => add(AlertStreamFailed(e, source: source)),
      onRecovered: () => add(AlertStreamRecovered(source: source)),
    ).listen((vm) => add(AlertReceived(vm)));
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

    await _configSub?.cancel();
    _configSub = _alertSourcesConfig().listen(
      (csv) => add(AlertConfigChanged(csv)),
    );
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
    final desired = <AlertSourceId>{
      for (final system in parsed.metro)
        AlertSourceId(AlertSourceKind.metro, system),
      for (final city in parsed.bus) AlertSourceId(AlertSourceKind.bus, city),
    };
    final current = _subs.keys
        .where(
          (s) =>
              s.kind == AlertSourceKind.metro || s.kind == AlertSourceKind.bus,
        )
        .toSet();

    final toRemove = current.difference(desired);
    final toAdd = desired.difference(current);
    if (toRemove.isEmpty && toAdd.isEmpty) return;

    for (final source in toRemove) {
      final sub = _subs.remove(source);
      await sub?.cancel();
    }
    for (final source in toAdd) {
      _listenSource(
        source,
        source.kind == AlertSourceKind.metro
            ? () => _repository.metroAlert(source.code)
            : () => _repository.busNews(source.code),
      );
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
    final updated = List<AlertViewModel>.from(state.activeAlerts)
      ..removeWhere((a) => a.message == event.alert.message);
    if (event.alert.level != AlertSeverity.green) {
      updated.add(event.alert);
    }
    emit(state.copyWith(activeAlerts: updated));
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
    await _cancelAll();
    return super.close();
  }
}
