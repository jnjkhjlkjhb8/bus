import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_state.dart';

void main() {
  test('AlertBloc does not subscribe on construction', () async {
    final bloc = AlertBloc();
    addTearDown(bloc.close);

    expect(bloc.hasActiveSubscriptions, isFalse);
  });

  test('AlertStreamFailed sets error state', () async {
    final bloc = AlertBloc();
    addTearDown(bloc.close);

    final next = expectLater(
      bloc.stream,
      emits(
        isA<AlertState>().having((s) => s.error, 'error', isA<OfflineError>()),
      ),
    );

    bloc.add(const AlertStreamFailed(OfflineError()));
    await next;
  });

  test('AlertStreamRecovered clears error', () async {
    final bloc = AlertBloc();
    addTearDown(bloc.close);

    final next = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<AlertState>().having((s) => s.error, 'error', isA<OfflineError>()),
        isA<AlertState>().having((s) => s.error, 'error', isNull),
      ]),
    );

    bloc
      ..add(const AlertStreamFailed(OfflineError()))
      ..add(const AlertStreamRecovered());
    await next;
  });
}
