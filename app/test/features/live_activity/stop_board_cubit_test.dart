import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/live_activity/live_activity_channel.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_car/features/live_activity/bloc/stop_board_cubit.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

/// Records every board call so tests can assert on stopName/rows without the
/// platform channel firing (mirrors `_CapturingChannel` in
/// journey_session_track_only_test.dart).
class _RecordingChannel extends LiveActivityChannel {
  final calls = <String>[];
  String? lastStopName;
  List<StopBoardRow>? lastRows;

  @override
  Future<void> startBoard(String stopName, List<StopBoardRow> rows) async {
    calls.add('start');
    lastStopName = stopName;
    lastRows = rows;
  }

  @override
  Future<void> updateBoard(String stopName, List<StopBoardRow> rows) async {
    calls.add('update');
    lastStopName = stopName;
    lastRows = rows;
  }

  @override
  Future<void> stop() async => calls.add('stop');
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
    session = JourneySessionBloc();
  });

  tearDown(() async {
    await etaCtrl.close();
    await session.close();
  });

  StopBoardCubit cubit() => StopBoardCubit(
    channel: channel,
    session: session,
    etaSource: (_, _) => etaCtrl.stream,
  );

  test('start sends rows sorted soonest-first and capped at 4', () async {
    final c = cubit()..start('Taipei', 'stop-1', '大安森林公園站');

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
    expect(c.state.active, isTrue);
    expect(c.state.stopName, '大安森林公園站');
    await c.close();
  });

  test('a row with no resolvable label falls back to em dash', () async {
    final c = cubit()..start('Taipei', 'stop-1', '測試站');
    etaCtrl.add([_arrival('9', '未知', 0, stopStatus: 99)]);
    await Future<void>.delayed(Duration.zero);
    expect(channel.lastRows!.single.etaLabel, '—');
    await c.close();
  });

  test('second frame calls updateBoard, not startBoard again', () async {
    final c = cubit()..start('Taipei', 'stop-1', '測試站');
    etaCtrl.add([_arrival('20', '公館', 0)]);
    await Future<void>.delayed(Duration.zero);
    etaCtrl.add([_arrival('20', '公館', 30)]);
    await Future<void>.delayed(Duration.zero);
    expect(channel.calls, ['start', 'update']);
    await c.close();
  });

  test('start cancels any live journey session (mutual exclusion)', () async {
    session.add(JourneyStarted(legs: [_leg()]));
    await session.stream.firstWhere((s) => s.phase == JourneyPhase.waiting);

    final c = cubit()..start('Taipei', 'stop-1', '測試站');
    final s = await session.stream.firstWhere(
      (s) => s.phase == JourneyPhase.done,
    );
    expect(s.phase, JourneyPhase.done);
    await c.close();
  });

  test('start is a no-op mutual-exclusion signal even without a live '
      'session', () async {
    // No JourneyStarted was ever dispatched; session stays idle and simply
    // ignores the cancel — this must not throw.
    final c = cubit();
    expect(() => c.start('Taipei', 'stop-1', '測試站'), returnsNormally);
    expect(session.state.phase, JourneyPhase.idle);
    await c.close();
  });

  test('stop cancels the subscription and stops the channel', () async {
    final c = cubit()..start('Taipei', 'stop-1', '測試站');
    etaCtrl.add([_arrival('20', '公館', 0)]);
    await Future<void>.delayed(Duration.zero);
    expect(etaCtrl.hasListener, isTrue);

    c.stop();
    await Future<void>.delayed(Duration.zero);
    expect(etaCtrl.hasListener, isFalse);
    expect(channel.calls.last, 'stop');
    expect(c.state.active, isFalse);
    await c.close();
  });

  test('close cancels a live subscription without leaking', () async {
    final c = cubit()..start('Taipei', 'stop-1', '測試站');
    expect(etaCtrl.hasListener, isTrue);
    await c.close();
    expect(etaCtrl.hasListener, isFalse);
  });
}
