import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';
import 'package:wheres_the_car/data/repositories/maas_repository.dart';
import 'package:wheres_the_car/features/go/bloc/plan_bloc.dart';
import 'package:wheres_the_car/features/go/bloc/plan_event.dart';
import 'package:wheres_the_car/features/go/bloc/plan_state.dart';

void main() {
  test('search success emits result', () async {
    final result = PlanResult(routes: [_route()]);
    final bloc = PlanBloc(repository: _FakeMaasRepository(result: result));
    addTearDown(bloc.close);

    final next = expectLater(
      bloc.stream,
      emitsThrough(
        isA<PlanState>()
            .having((s) => s.status, 'status', PlanStatus.success)
            .having((s) => s.result, 'result', result),
      ),
    );

    bloc.add(_search());
    await next;
  });

  test('search failure emits error state', () async {
    final bloc = PlanBloc(
      repository: _FakeMaasRepository(error: StateError('boom')),
    );
    addTearDown(bloc.close);

    final next = expectLater(
      bloc.stream,
      emitsThrough(
        isA<PlanState>()
            .having((s) => s.status, 'status', PlanStatus.failure)
            .having((s) => s.error, 'error', contains('boom')),
      ),
    );

    bloc.add(_search());
    await next;
  });

  test('search success enters results phase with the fastest selected',
      () async {
    final result = PlanResult(routes: [_route(), _route()]);
    final bloc = PlanBloc(repository: _FakeMaasRepository(result: result));
    addTearDown(bloc.close);

    final next = expectLater(
      bloc.stream,
      emitsThrough(
        isA<PlanState>()
            .having((s) => s.status, 'status', PlanStatus.success)
            .having((s) => s.selectedRouteIndex, 'selectedRouteIndex', 0)
            .having((s) => s.previewing, 'previewing', false),
      ),
    );

    bloc.add(_search());
    await next;
  });

  test('selecting a route enters the preview phase', () async {
    final bloc = PlanBloc(repository: _FakeMaasRepository());
    addTearDown(bloc.close);

    final next = expectLater(
      bloc.stream,
      emitsThrough(
        isA<PlanState>()
            .having((s) => s.selectedRouteIndex, 'selectedRouteIndex', 2)
            .having((s) => s.previewing, 'previewing', true),
      ),
    );

    bloc.add(const RouteSelected(index: 2));
    await next;
  });

  test('closing a results preview returns to results, keeping the result',
      () async {
    final result = PlanResult(routes: [_route(), _route()]);
    final bloc = PlanBloc(repository: _FakeMaasRepository(result: result));
    addTearDown(bloc.close);

    bloc.add(_search());
    await bloc.stream.firstWhere((s) => s.status == PlanStatus.success);
    bloc.add(const RouteSelected(index: 1));
    await bloc.stream.firstWhere((s) => s.previewing);

    final next = expectLater(
      bloc.stream,
      emitsThrough(
        isA<PlanState>()
            .having((s) => s.previewing, 'previewing', false)
            .having((s) => s.result, 'result', result)
            .having((s) => s.selectedRouteIndex, 'selectedRouteIndex', 1),
      ),
    );

    bloc.add(const PreviewClosed());
    await next;
  });

  test('a new search resets an active preview back to results', () async {
    final bloc = PlanBloc(
      repository: _FakeMaasRepository(result: PlanResult(routes: [_route()])),
    );
    addTearDown(bloc.close);

    bloc.add(const RouteSelected(index: 0));
    await bloc.stream.firstWhere((s) => s.previewing);

    final next = expectLater(
      bloc.stream,
      emitsThrough(
        isA<PlanState>()
            .having((s) => s.status, 'status', PlanStatus.success)
            .having((s) => s.previewing, 'previewing', false),
      ),
    );

    bloc.add(_search());
    await next;
  });

  test('opening a saved route lands directly in preview', () async {
    final bloc = PlanBloc(repository: _FakeMaasRepository());
    addTearDown(bloc.close);

    final next = expectLater(
      bloc.stream,
      emitsThrough(
        isA<PlanState>()
            .having((s) => s.status, 'status', PlanStatus.success)
            .having((s) => s.previewing, 'previewing', true)
            .having((s) => s.previewFromSaved, 'previewFromSaved', true)
            .having((s) => s.result?.routes.length, 'routes', 1),
      ),
    );

    bloc.add(SavedRouteOpened(_route()));
    await next;
  });

  test('closing a saved-route preview clears the injected result', () async {
    final bloc = PlanBloc(repository: _FakeMaasRepository());
    addTearDown(bloc.close);

    bloc.add(SavedRouteOpened(_route()));
    await bloc.stream.firstWhere((s) => s.previewing);

    final next = expectLater(
      bloc.stream,
      emitsThrough(
        isA<PlanState>()
            .having((s) => s.status, 'status', PlanStatus.initial)
            .having((s) => s.result, 'result', null)
            .having((s) => s.previewing, 'previewing', false)
            .having((s) => s.previewFromSaved, 'previewFromSaved', false),
      ),
    );

    bloc.add(const PreviewClosed());
    await next;
  });

  test('ending navigation returns to the previewed route', () async {
    final result = PlanResult(routes: [_route(), _route()]);
    final bloc = PlanBloc(repository: _FakeMaasRepository(result: result));
    addTearDown(bloc.close);

    bloc.add(_search());
    await bloc.stream.firstWhere((s) => s.status == PlanStatus.success);
    bloc.add(const RouteSelected(index: 1));
    await bloc.stream.firstWhere((s) => s.previewing);
    bloc.add(const NavigationStarted());
    await bloc.stream.firstWhere((s) => s.activeLegIndex != null);

    final next = expectLater(
      bloc.stream,
      emitsThrough(
        isA<PlanState>()
            .having((s) => s.activeLegIndex, 'activeLegIndex', null)
            .having((s) => s.previewing, 'previewing', true)
            .having((s) => s.selectedRouteIndex, 'selectedRouteIndex', 1),
      ),
    );

    bloc.add(const NavigationEnded());
    await next;
  });

  test('navigation events update and clear active indexes', () async {
    final bloc = PlanBloc(repository: _FakeMaasRepository());
    addTearDown(bloc.close);

    bloc
      ..add(const NavigationStarted())
      ..add(const StopArrived(legIndex: 1, stopIndex: 3))
      ..add(const NavigationEnded());

    await expectLater(
      bloc.stream,
      emitsInOrder([
        // The constructor's SavedRoutesLoaded emits first; skip past it.
        emitsThrough(
          isA<PlanState>().having((s) => s.activeLegIndex, 'activeLegIndex', 0),
        ),
        isA<PlanState>().having((s) => s.activeStopIndex, 'activeStopIndex', 3),
        isA<PlanState>().having(
          (s) => s.activeLegIndex,
          'activeLegIndex',
          null,
        ),
      ]),
    );
  });
}

PlanSearchRequested _search() => const PlanSearchRequested(
  fromLat: 25,
  fromLon: 121,
  toLat: 25.1,
  toLon: 121.1,
  date: '2026-07-03',
  time: '12:00',
);

PlanRoute _route() => const PlanRoute(
  travelTime: 600,
  startTime: '12:00',
  endTime: '12:10',
  transfers: 0,
  sections: [],
);

class _FakeMaasRepository implements MaasRepository {
  _FakeMaasRepository({PlanResult? result, this.error})
    : result = result ?? const PlanResult(routes: []);

  final PlanResult result;
  final Error? error;

  @override
  Future<PlanResult> plan({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required String date,
    required String time,
    bool arriveBy = false,
    double gc = 0.0,
    List<int> transitModes = const [3, 4, 5, 6, 7, 8, 9],
    int top = 5,
    int transferMin = 15,
    int transferMax = 60,
    int firstMileMode = 0,
    int firstMileTime = 10,
    int lastMileMode = 0,
    int lastMileTime = 10,
  }) async {
    final error = this.error;
    if (error != null) throw error;
    return result;
  }
}
