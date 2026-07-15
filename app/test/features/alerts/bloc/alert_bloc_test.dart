import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';
import 'package:wheres_the_car/data/repositories/alert_repository.dart';
import 'package:wheres_the_car/data/repositories/settings_repository.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_state.dart';

import '../../../support/helpers/in_memory_settings_store.dart';

void main() {
  test('AlertReceived adds a non-green alert to active alerts', () async {
    final bloc = AlertBloc();
    addTearDown(bloc.close);

    const alert = AlertViewModel(
      message: '中和線延誤',
      level: AlertSeverity.red,
      rawJson: {},
    );

    final next = expectLater(
      bloc.stream,
      emits(
        isA<AlertState>().having(
          (s) => s.activeAlerts,
          'activeAlerts',
          contains(alert),
        ),
      ),
    );

    bloc.add(const AlertReceived(alert));
    await next;
  });

  // These two handlers are what the passthrough seam's onFailure/onRecovered
  // callbacks add when the four alert streams drop and recover. The seam's
  // callback pass-through itself is covered in test/data/live/arrival_feed_test.
  test(
    'AlertStreamFailed sets the error, AlertStreamRecovered clears it',
    () async {
      final bloc = AlertBloc();
      addTearDown(bloc.close);

      final sawError = expectLater(
        bloc.stream,
        emits(
          isA<AlertState>().having(
            (s) => s.error,
            'error',
            isA<OfflineError>(),
          ),
        ),
      );
      bloc.add(const AlertStreamFailed(OfflineError()));
      await sawError;

      final cleared = expectLater(
        bloc.stream,
        emits(isA<AlertState>().having((s) => s.error, 'error', isNull)),
      );
      bloc.add(const AlertStreamRecovered());
      await cleared;
    },
  );

  group('source-scoped health (F32)', () {
    const metroA = AlertSourceId(AlertSourceKind.metro, 'TRTC');
    const metroB = AlertSourceId(AlertSourceKind.metro, 'KRTC');

    test(
      'two failed sources with one recovery keeps the global error set',
      () async {
        final bloc = AlertBloc();
        addTearDown(bloc.close);

        bloc
          ..add(const AlertStreamFailed(OfflineError(), source: metroA))
          ..add(const AlertStreamFailed(OfflineError(), source: metroB));
        await pumpEventQueue();
        expect(bloc.state.error, isA<OfflineError>());
        expect(bloc.state.sourceHealth.keys, containsAll([metroA, metroB]));

        bloc.add(const AlertStreamRecovered(source: metroA));
        await pumpEventQueue();

        // The recovered source cleared its own failure only.
        expect(bloc.state.sourceHealth, isNot(contains(metroA)));
        expect(bloc.state.sourceHealth, contains(metroB));
        // The other source is still down, so the global error must not clear.
        expect(bloc.state.error, isA<OfflineError>());
      },
    );

    test('recovering an untracked source is a no-op', () async {
      final bloc = AlertBloc();
      addTearDown(bloc.close);

      bloc.add(const AlertStreamRecovered(source: metroA));
      await pumpEventQueue();
      expect(bloc.state.sourceHealth, isEmpty);
      expect(bloc.state.error, isNull);
    });
  });

  group('dynamic alert_sources config (F33)', () {
    late _RecordingAlertRepository repository;
    late StreamController<String> config;
    late AlertBloc bloc;

    setUp(() {
      repository = _RecordingAlertRepository();
      config = StreamController<String>();
      bloc = AlertBloc(
        repository: repository,
        alertSourcesConfig: () => config.stream,
      );
    });

    tearDown(() async {
      await bloc.close();
      await config.close();
    });

    test('startup subscribes the static and initial dynamic sources', () async {
      bloc.add(const AlertStarted());
      await pumpEventQueue();
      config.add('metro:TRTC,bus:Taipei');
      await pumpEventQueue();

      expect(
        repository.subscribed,
        containsAll(['tra', 'thsr', 'metro:TRTC', 'bus:Taipei']),
      );
    });

    test('an identical config revision causes no resubscribe', () async {
      bloc.add(const AlertStarted());
      await pumpEventQueue();
      config.add('metro:TRTC,bus:Taipei');
      await pumpEventQueue();
      final before = List<String>.from(repository.subscribed);

      config.add('metro:TRTC,bus:Taipei');
      await pumpEventQueue();

      expect(repository.subscribed, before);
    });

    test(
      'a config revision replaces only the affected subscriptions, '
      'kept sources are never touched',
      () async {
        bloc.add(const AlertStarted());
        await pumpEventQueue();
        config.add('metro:TRTC,bus:Taipei');
        await pumpEventQueue();

        config.add('metro:TRTC,bus:Taichung');
        await pumpEventQueue();

        expect(repository.cancelled, contains('bus:Taipei'));
        expect(repository.subscribed, contains('bus:Taichung'));
        // The kept metro subscription must never be cancelled.
        expect(repository.cancelled, isNot(contains('metro:TRTC')));
        expect(
          repository.subscribed.where((s) => s == 'metro:TRTC').length,
          1,
        );
      },
    );

    test('close() awaits every subscription cancellation', () async {
      bloc.add(const AlertStarted());
      await pumpEventQueue();
      config.add('metro:TRTC,bus:Taipei');
      await pumpEventQueue();

      await bloc.close();

      expect(
        repository.cancelled,
        containsAll(['tra', 'thsr', 'metro:TRTC', 'bus:Taipei']),
      );
    });
  });
}

/// Records subscribe/cancel calls instead of hitting gRPC, so config-revision
/// diffing (F33) can be asserted without a network dependency.
class _RecordingAlertRepository extends AlertRepository {
  _RecordingAlertRepository()
    : super(settings: SettingsRepository(store: InMemorySettingsStore()));

  final List<String> subscribed = [];
  final List<String> cancelled = [];

  Stream<AlertViewModel> _stream(String key) {
    subscribed.add(key);
    final controller = StreamController<AlertViewModel>(
      onCancel: () => cancelled.add(key),
    );
    return controller.stream;
  }

  @override
  Stream<AlertViewModel> traAlert() => _stream('tra');

  @override
  Stream<AlertViewModel> thsrAlert() => _stream('thsr');

  @override
  Stream<AlertViewModel> metroAlert(String system) => _stream('metro:$system');

  @override
  Stream<AlertViewModel> busNews(String city) => _stream('bus:$city');
}
