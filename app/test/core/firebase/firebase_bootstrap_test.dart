import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/core/firebase/firebase_bootstrap.dart';

/// `FirebaseBootstrap.ensureCoreInitialized`'s single-flight
/// guard and `initFailSoft` propagating a failure instead of swallowing it.
///
/// `singleFlightCoreInit` is tested directly (via `@visibleForTesting`)
/// rather than through `ensureCoreInitialized`/`init` because
/// `FirebaseGate.enabled` is compile-time `false` under `flutter test`
/// (no `--dart-define=FIREBASE_ENABLED=true`), which would make every call
/// through the public entry points a no-op regardless of what's being
/// tested.
void main() {
  setUp(FirebaseBootstrap.resetCoreInitForTesting);

  group('singleFlightCoreInit', () {
    test('concurrent callers share one in-flight initializer call', () async {
      var callCount = 0;
      final gate = Completer<void>();
      Future<void> initializer() async {
        callCount++;
        await gate.future;
      }

      final first = FirebaseBootstrap.singleFlightCoreInit(initializer);
      final second = FirebaseBootstrap.singleFlightCoreInit(initializer);

      expect(callCount, 1);
      gate.complete();
      await first;
      await second;

      expect(callCount, 1);
    });

    test(
      'a failure is not permanently cached — the next call retries',
      () async {
        var callCount = 0;
        Future<void> failingOnce() async {
          callCount++;
          if (callCount == 1) throw StateError('no network');
        }

        await expectLater(
          FirebaseBootstrap.singleFlightCoreInit(failingOnce),
          throwsA(isA<StateError>()),
        );
        // The in-flight future's catchError (which clears the memoized
        // future) runs in a microtask after the throw above is observed.
        await Future<void>.delayed(Duration.zero);

        await FirebaseBootstrap.singleFlightCoreInit(failingOnce);

        expect(callCount, 2);
      },
    );
  });

  group('initFailSoft', () {
    test('rethrows after logging so a caller sees the failure', () async {
      Future<void> failingInitializer({Future<void>? hiveReady}) async {
        throw StateError('firebase down');
      }

      await expectLater(
        FirebaseBootstrap.initFailSoft(initializer: failingInitializer),
        throwsA(isA<StateError>()),
      );
    });

    test('rethrows on timeout', () async {
      Future<void> hangingInitializer({Future<void>? hiveReady}) =>
          Completer<void>().future;

      await expectLater(
        FirebaseBootstrap.initFailSoft(
          initializer: hangingInitializer,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('resolves normally when the initializer succeeds', () async {
      Future<void> okInitializer({Future<void>? hiveReady}) async {}

      await expectLater(
        FirebaseBootstrap.initFailSoft(initializer: okInitializer),
        completes,
      );
    });
  });
}
