import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_state.dart';

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

  // These two handlers are what LiveData's onFailure/onRecovered callbacks add
  // when the four alert streams drop and recover. The wrapper's callback
  // pass-through itself is covered in test/core/grpc/live_data_test.dart.
  test('AlertStreamFailed sets the error, AlertStreamRecovered clears it',
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
  });
}
