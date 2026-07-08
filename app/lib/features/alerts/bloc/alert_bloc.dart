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

class AlertBloc extends Bloc<AlertEvent, AlertState> {
  AlertBloc({AlertRepository? repository})
    : _repository = repository ?? AlertRepository.instance,
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
  }

  final AlertRepository _repository;

  void _persistRead(Set<String> read) {
    unawaited(_repository.persistReadAlerts(read));
  }

  final List<StreamSubscription<AlertViewModel>> _subs = [];

  bool get hasActiveSubscriptions => _subs.isNotEmpty;

  Future<void> _onStarted(AlertStarted _, Emitter<AlertState> emit) async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();

    void listen(Stream<AlertViewModel> Function() source) {
      _subs.add(
        ArrivalFeed.passthrough(
          source: source,
          onFailure: (e) => add(AlertStreamFailed(e)),
          onRecovered: () => add(const AlertStreamRecovered()),
        ).listen((vm) => add(AlertReceived(vm))),
      );
    }

    listen(_repository.traAlert);
    listen(_repository.thsrAlert);
    final sources = parseAlertSources(AppConfig.getString('alert_sources'));
    for (final system in sources.metro) {
      listen(() => _repository.metroAlert(system));
    }
    for (final city in sources.bus) {
      listen(() => _repository.busNews(city));
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
    emit(state.copyWith(error: event.error));
  }

  void _onStreamRecovered(AlertStreamRecovered _, Emitter<AlertState> emit) {
    emit(state.copyWith(clearError: true));
  }

  @override
  Future<void> close() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    return super.close();
  }
}
