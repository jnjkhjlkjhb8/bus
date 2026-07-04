import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/grpc/live_data.dart';

Future<void> eventually(
  bool Function() done, {
  Duration timeout = const Duration(milliseconds: 300),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue);
}

void main() {
  test('forwards data from the source', () async {
    final controller = StreamController<int>();
    final got = <int>[];
    final live = LiveData<int>.watch(
      source: () => controller.stream,
      onData: got.add,
    );
    addTearDown(live.cancel);

    controller
      ..add(1)
      ..add(2);
    await Future<void>.delayed(Duration.zero);

    expect(got, [1, 2]);
  });

  test('cancel stops delivery', () async {
    final controller = StreamController<int>.broadcast();
    final got = <int>[];
    final live = LiveData<int>.watch(
      source: () => controller.stream,
      onData: got.add,
    );

    controller.add(1);
    await Future<void>.delayed(Duration.zero);
    await live.cancel();
    controller.add(2);
    await Future<void>.delayed(Duration.zero);

    expect(got, [1]);
  });

  test('null onFailure does not throw when the source errors', () async {
    final controller = StreamController<int>();
    final live = LiveData<int>.watch(
      source: () => controller.stream,
      onData: (_) {},
      // onFailure intentionally omitted -- bike/rail path
    );
    addTearDown(live.cancel);

    controller.addError(const OfflineError());
    await Future<void>.delayed(Duration.zero);
    // Reaching here without an unhandled exception is the assertion.
    expect(true, isTrue);
  });

  // REVIEW CARRY (Task 5): LiveData.watch must forward onFailure straight
  // through to ResilientSubscription. A terminal error (unauthenticated)
  // trips the failure callback immediately.
  test('passes onFailure through to the source', () async {
    final failures = <AppError>[];
    final live = LiveData<int>.watch(
      source: () => Stream<int>.error(const GrpcError.unauthenticated()),
      onData: (_) {},
      onFailure: failures.add,
    );
    addTearDown(live.cancel);

    await eventually(() => failures.isNotEmpty);
    expect(failures.single, isA<AppError>());
  });

  // REVIEW CARRY (Task 5): LiveData.watch must forward onRecovered straight
  // through. A single non-terminal error followed by a value drives one
  // resubscribe-then-recover cycle; recovery waits out the wrapper's
  // (untunable) base retry delay, so allow a generous window.
  test('passes onRecovered through to the source', () async {
    var recovered = 0;
    var attempt = 0;
    final live = LiveData<int>.watch(
      source: () {
        attempt++;
        if (attempt == 1) {
          return Stream<int>.error(const GrpcError.unavailable());
        }
        return Stream<int>.value(7);
      },
      onData: (_) {},
      onRecovered: () => recovered++,
    );
    addTearDown(live.cancel);

    await eventually(
      () => recovered == 1,
      timeout: const Duration(seconds: 5),
    );
    expect(recovered, 1);
  });
}
