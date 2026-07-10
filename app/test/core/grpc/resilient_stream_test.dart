import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/grpc/resilient_stream.dart';

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
  test('resubscribes with backoff after error', () async {
    var subscribeCount = 0;
    final sub = ResilientSubscription<int>(
      source: () {
        subscribeCount++;
        return Stream<int>.error(const GrpcError.unavailable());
      },
      onData: (_) {},
      onFailure: (_) {},
      baseDelay: const Duration(milliseconds: 1),
      maxDelay: const Duration(milliseconds: 4),
      reportError: (_, _) {},
    );

    await eventually(() => subscribeCount >= 3);
    expect(subscribeCount, greaterThanOrEqualTo(3));
    await sub.cancel();
  });

  test('onFailure fires once at threshold', () async {
    final failures = <AppError>[];
    final sub = ResilientSubscription<int>(
      source: () => Stream<int>.error(const GrpcError.unavailable()),
      onData: (_) {},
      onFailure: failures.add,
      maxFailures: 2,
      baseDelay: const Duration(milliseconds: 1),
      maxDelay: const Duration(milliseconds: 1),
      reportError: (_, _) {},
    );

    await eventually(() => failures.isNotEmpty);
    expect(failures.length, 1);
    expect(failures.single, isA<OfflineError>());
    await sub.cancel();
  });

  test('data resets failures and calls onRecovered', () async {
    var failed = 0;
    var recovered = 0;
    var attempt = 0;
    final sub = ResilientSubscription<int>(
      source: () {
        attempt++;
        if (attempt == 1) {
          return Stream<int>.error(const GrpcError.unavailable());
        }
        return Stream<int>.value(42);
      },
      onData: (_) {},
      onFailure: (_) => failed++,
      onRecovered: () => recovered++,
      baseDelay: const Duration(milliseconds: 1),
      reportError: (_, _) {},
    );

    await eventually(() => recovered == 1);
    expect(recovered, 1);
    expect(failed, 0);
    await sub.cancel();
  });

  test('cancel stops retrying', () async {
    var subscribeCount = 0;
    final sub = ResilientSubscription<int>(
      source: () {
        subscribeCount++;
        return Stream<int>.error(const GrpcError.unavailable());
      },
      onData: (_) {},
      onFailure: (_) {},
      baseDelay: const Duration(milliseconds: 1),
      reportError: (_, _) {},
    );

    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(subscribeCount, 1);
  });

  test('uses the injected retry delay', () async {
    Duration? observed;
    final sub = ResilientSubscription<int>(
      source: () => Stream<int>.error(const GrpcError.unavailable()),
      onData: (_) {},
      onFailure: (_) {},
      retryDelay: (delay) {
        observed ??= delay;
        return const Duration(days: 1);
      },
      reportError: (_, _) {},
    );

    await eventually(() => observed != null);
    expect(observed, const Duration(seconds: 2));
    await sub.cancel();
  });
}
