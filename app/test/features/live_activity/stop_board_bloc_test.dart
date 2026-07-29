import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/core/live_activity/live_activity_channel.dart';
import 'package:wheres_the_bus/data/models/bus_models.dart';
import 'package:wheres_the_bus/data/models/plan_models.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/stop_board_bloc.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/stop_board_event.dart';
import 'package:wheres_the_bus/features/live_activity/model/journey_models.dart';

import '../../support/helpers/i18n.dart';

/// Records every board call so tests can assert on stopName/rows without the
/// platform channel firing (mirrors `_CapturingChannel` in
/// journey_session_track_only_test.dart). Mints leases the same way the
/// real channel would, so a lease-plumbing bug in the bloc still surfaces.
class _RecordingChannel extends LiveActivityChannel {
  final calls = <String>[];
  String? lastStopName;
  List<StopBoardRow>? lastRows;
  int _lease = 0;

  @override
  Future<int> startBoard(String stopName, List<StopBoardRow> rows) async {
    calls.add('start');
    lastStopName = stopName;
    lastRows = rows;
    return ++_lease;
  }

  @override
  Future<void> updateBoard(
    int lease,
    String stopName,
    List<StopBoardRow> rows,
  ) async {
    calls.add('update');
    lastStopName = stopName;
    lastRows = rows;
  }

  @override
  Future<void> stop(int lease) async => calls.add('stop');
}

/// A channel whose startBoard round-trip completes only when the test says
/// so, to interleave a second arrivals frame inside the first start's await
/// gap (Bloc's default event transformer is concurrent, so a second
/// BoardArrivalsReceived handler can run before the first one's await
/// resumes).
class _SlowStartChannel extends LiveActivityChannel {
  final calls = <String>[];
  final startGates = <Completer<void>>[];
  int _lease = 0;

  @override
  Future<int> startBoard(String stopName, List<StopBoardRow> rows) async {
    calls.add('start');
    final gate = Completer<void>();
    startGates.add(gate);
    await gate.future;
    return ++_lease;
  }

  @override
  Future<void> updateBoard(
    int lease,
    String stopName,
    List<StopBoardRow> rows,
  ) async => calls.add('update');

  @override
  Future<void> stop(int lease) async => calls.add('stop');
}

BusStopArrival _arrival(
  String route,
  String dest,
  int seconds, {
  int stopStatus = 0,
  String nextBusTime = '',
}) => BusStopArrival(
  stationId: 'stop-1',
  subRouteUid: 'sub-$route',
  routeName: route,
  destination: dest,
  estimateSeconds: seconds,
  stopStatus: stopStatus,
  nextBusTime: nextBusTime,
);

JourneyLeg _leg() => const JourneyLeg(
  kind: JourneyLegKind.bus,
  routeLabel: '307 往板橋',
  boardStop: '捷運昆陽站',
  alightStop: '板橋',
  stopNames: [],
  identity: PlanIdentity(
    routeType: 'bus',
    routeKey: 'sub-307',
    direction: '0',
    departureStopKey: 'stop-1',
    arrivalStopKey: '',
    supported: false,
  ),
  leadingWalkMinutes: 0,
  scheduledDeparture: null,
  scheduledArrival: null,
  boardLocation: PlanPoint(lat: 25, lng: 121.5),
  stopLocations: [],
);

void main() {
  late _RecordingChannel channel;
  late StreamController<List<BusStopArrival>> etaCtrl;
  late JourneySessionBloc session;

  setUp(() {
    channel = _RecordingChannel();
    etaCtrl = StreamController<List<BusStopArrival>>.broadcast();
    session = JourneySessionBloc(liveActivityEnabled: () => true);
  });

  tearDown(() async {
    await etaCtrl.close();
    await session.close();
  });

  StopBoardBloc bloc() => StopBoardBloc(
    i18n: zhStrings,
    channel: channel,
    session: session,
    etaSource: (_, _) => etaCtrl.stream,
  );

  test('start sends rows sorted soonest-first and capped at 4', () async {
    final b = bloc()
      ..add(const StopBoardStarted('Taipei', 'stop-1', '大安森林公園站'));
    // Dispatching an event only queues it — the subscription to etaCtrl
    // isn't live until the bloc's event loop has actually processed
    // StopBoardStarted, unlike the old Cubit's synchronous start() call.
    await Future<void>.delayed(Duration.zero);

    etaCtrl.add([
      _arrival('672', '科技大樓', 600),
      _arrival('20', '公館', 0),
      _arrival('295', '南港', 120),
      _arrival('88', '信義', 300),
      _arrival('15', '大直', 60),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(channel.calls, ['start']);
    expect(channel.lastStopName, '大安森林公園站');
    final rows = channel.lastRows!;
    expect(rows.length, 4);
    expect(rows.map((r) => r.routeNumber), ['20', '15', '295', '88']);
    expect(rows[0].destination, '往公館');
    expect(rows[0].etaLabel, '進站中');
    expect(b.state.active, isTrue);
    expect(b.state.stopName, '大安森林公園站');
    await b.close();
  });

  test('a row with no resolvable label falls back to em dash', () async {
    final b = bloc()..add(const StopBoardStarted('Taipei', 'stop-1', '測試站'));
    await Future<void>.delayed(Duration.zero);
    etaCtrl.add([_arrival('9', '未知', 0, stopStatus: 99)]);
    await Future<void>.delayed(Duration.zero);
    expect(channel.lastRows!.single.etaLabel, '—');
    await b.close();
  });

  test('second frame calls updateBoard, not startBoard again', () async {
    final b = bloc()..add(const StopBoardStarted('Taipei', 'stop-1', '測試站'));
    await Future<void>.delayed(Duration.zero);
    etaCtrl.add([_arrival('20', '公館', 0)]);
    await Future<void>.delayed(Duration.zero);
    etaCtrl.add([_arrival('20', '公館', 30)]);
    await Future<void>.delayed(Duration.zero);
    expect(channel.calls, ['start', 'update']);
    await b.close();
  });

  test('start cancels any live journey session (mutual exclusion)', () async {
    session.add(JourneyStarted(legs: [_leg()]));
    await session.stream.firstWhere((s) => s.phase == JourneyPhase.waiting);

    final b = bloc()..add(const StopBoardStarted('Taipei', 'stop-1', '測試站'));
    final s = await session.stream.firstWhere(
      (s) => s.phase == JourneyPhase.done,
    );
    expect(s.phase, JourneyPhase.done);
    await b.close();
  });

  test('start is a no-op mutual-exclusion signal even without a live '
      'session', () async {
    // No JourneyStarted was ever dispatched; session stays idle and simply
    // ignores the cancel — this must not throw.
    final b = bloc();
    expect(
      () => b.add(const StopBoardStarted('Taipei', 'stop-1', '測試站')),
      returnsNormally,
    );
    await Future<void>.delayed(Duration.zero);
    expect(session.state.phase, JourneyPhase.idle);
    await b.close();
  });

  test('stop cancels the subscription and stops the channel', () async {
    final b = bloc()..add(const StopBoardStarted('Taipei', 'stop-1', '測試站'));
    await Future<void>.delayed(Duration.zero);
    etaCtrl.add([_arrival('20', '公館', 0)]);
    await Future<void>.delayed(Duration.zero);
    expect(etaCtrl.hasListener, isTrue);

    b.add(const StopBoardStopped());
    await Future<void>.delayed(Duration.zero);
    expect(etaCtrl.hasListener, isFalse);
    expect(channel.calls.last, 'stop');
    expect(b.state.active, isFalse);
    await b.close();
  });

  test(
    'a second arrivals frame during the first startBoard round-trip does '
    'not start a second board (no double start)',
    () async {
      final slow = _SlowStartChannel();
      final b = StopBoardBloc(
        i18n: zhStrings,
        channel: slow,
        session: session,
        etaSource: (_, _) => etaCtrl.stream,
      )..add(const StopBoardStarted('Taipei', 'stop-1', '測試站'));
      await Future<void>.delayed(Duration.zero);

      // Frame 1 kicks off startBoard, which parks on its gate.
      etaCtrl.add([_arrival('20', '公館', 0)]);
      await Future<void>.delayed(Duration.zero);
      expect(slow.calls, ['start']);

      // Frame 2 lands while the first startBoard is still in flight. Bloc's
      // default transformer runs handlers concurrently, so without a
      // synchronous guard this would mint a second lease via startBoard.
      etaCtrl.add([_arrival('20', '公館', 30)]);
      await Future<void>.delayed(Duration.zero);
      expect(slow.calls, ['start']);
      expect(slow.startGates.length, 1);

      // Release the round-trip; subsequent frames update the single board.
      slow.startGates.single.complete();
      await Future<void>.delayed(Duration.zero);
      etaCtrl.add([_arrival('20', '公館', 60)]);
      await Future<void>.delayed(Duration.zero);
      expect(slow.calls, ['start', 'update']);

      await b.close();
    },
  );

  test('close cancels a live subscription without leaking', () async {
    final b = bloc()..add(const StopBoardStarted('Taipei', 'stop-1', '測試站'));
    await Future<void>.delayed(Duration.zero);
    expect(etaCtrl.hasListener, isTrue);
    await b.close();
    expect(etaCtrl.hasListener, isFalse);
  });
}
