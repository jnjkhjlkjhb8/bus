import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/grpc/live_data.dart';

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
}
