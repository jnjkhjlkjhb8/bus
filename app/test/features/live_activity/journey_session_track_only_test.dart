import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/live_activity/live_activity_channel.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

/// Captures the last content pushed through the platform channel so tests
/// can assert on `_content()`'s output without the method channel firing.
class _CapturingChannel extends LiveActivityChannel {
  LiveActivityContent? last;

  @override
  Future<void> start(LiveActivityContent content) async => last = content;

  @override
  Future<void> update(LiveActivityContent content) async => last = content;

  @override
  Future<void> stop() async {}
}

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
  late StreamController<Duration?> etaCtrl;
  late StreamController<List<BusStopEtaViewModel>> routeEtaCtrl;
  JourneySessionBloc bloc({
    Duration linger = const Duration(minutes: 2),
    LiveActivityChannel? channel,
  }) => JourneySessionBloc(
    etaStream: (_) => etaCtrl.stream,
    routeEtaStream: (_) => routeEtaCtrl.stream,
    trackOnlyLinger: linger,
    channel: channel,
  );

  setUp(() {
    etaCtrl = StreamController<Duration?>.broadcast();
    routeEtaCtrl = StreamController<List<BusStopEtaViewModel>>.broadcast();
  });
  tearDown(() => Future.wait([etaCtrl.close(), routeEtaCtrl.close()]));

  test('trackOnly session waits without suggesting boarding at zero', () async {
    final b = bloc()..add(JourneyStarted(legs: [_leg()], trackOnly: true));
    final started = await b.stream.firstWhere(
      (s) => s.phase == JourneyPhase.waiting,
    );
    expect(started.trackOnly, isTrue);
    etaCtrl.add(Duration.zero);
    final s = await b.stream.firstWhere((s) => s.eta == Duration.zero);
    expect(s.suggestBoarding, isFalse);
    expect(s.phase, JourneyPhase.waiting);
    await b.close();
  });

  test('trackOnly ignores board confirmations', () async {
    final b = bloc()..add(JourneyStarted(legs: [_leg()], trackOnly: true));
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.waiting);
    // A cancel still lands after the ignored board event, proving the phase
    // never left waiting.
    b
      ..add(const BoardConfirmed())
      ..add(const JourneyCancelled());
    final s = await b.stream.firstWhere((s) => s.phase == JourneyPhase.done);
    expect(s.trackOnly, isTrue);
    await b.close();
  });

  test('eta jumping back up after arrival ends a trackOnly session', () async {
    final b = bloc()..add(JourneyStarted(legs: [_leg()], trackOnly: true));
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.waiting);
    etaCtrl.add(Duration.zero);
    await b.stream.firstWhere((s) => s.eta == Duration.zero);
    // The stream now counts down the following bus.
    etaCtrl.add(const Duration(minutes: 9));
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.done);
    await b.close();
  });

  test('trackOnly session lingers then ends after arrival', () async {
    final b = bloc(linger: const Duration(milliseconds: 50))
      ..add(JourneyStarted(legs: [_leg()], trackOnly: true));
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.waiting);
    etaCtrl.add(Duration.zero);
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.done);
    await b.close();
  });

  test('navigation sessions still suggest boarding at zero', () async {
    final b = bloc()..add(JourneyStarted(legs: [_leg()]));
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.waiting);
    etaCtrl.add(Duration.zero);
    final s = await b.stream.firstWhere((s) => s.eta == Duration.zero);
    expect(s.suggestBoarding, isTrue);
    expect(s.trackOnly, isFalse);
    await b.close();
  });

  test('trackOnly session carries a plate', () async {
    final b = bloc()
      ..add(
        JourneyStarted(legs: [_leg()], trackOnly: true, plate: 'KKA-1288'),
      );
    final s = await b.stream.firstWhere(
      (s) => s.phase == JourneyPhase.waiting,
    );
    expect(s.plate, 'KKA-1288');
    await b.close();
  });

  test('JourneyStarted without a plate leaves state.plate null', () async {
    final b = bloc()..add(JourneyStarted(legs: [_leg()], trackOnly: true));
    final s = await b.stream.firstWhere(
      (s) => s.phase == JourneyPhase.waiting,
    );
    expect(s.plate, isNull);
    await b.close();
  });

  test(
    'pinned session computes live stops-remaining from the route-ETA stream',
    () async {
      final channel = _CapturingChannel();
      final b = bloc(channel: channel)
        ..add(
          JourneyStarted(legs: [_leg()], trackOnly: true, plate: 'KKA-1288'),
        );
      await b.stream.firstWhere((s) => s.phase == JourneyPhase.waiting);
      expect(routeEtaCtrl.hasListener, isTrue);

      routeEtaCtrl.add(const [
        // Target: the leg's alight stop (departureStopKey 'stop-1'), 10
        // stops down the route.
        BusStopEtaViewModel(
          stopUid: 'stop-1',
          direction: 0,
          sequence: 10,
          estimateSeconds: 0,
          nextBusTime: '',
          stopStatus: 0,
          vehiclePlates: [],
        ),
        // The pinned plate currently sits 3 stops before the target.
        BusStopEtaViewModel(
          stopUid: 'stop-0',
          direction: 0,
          sequence: 7,
          estimateSeconds: 0,
          nextBusTime: '',
          stopStatus: 0,
          vehiclePlates: ['KKA-1288'],
          vehicles: [
            BusVehiclePosition(
              plate: 'KKA-1288',
              lat: 25,
              lon: 121.5,
              azimuth: 0,
            ),
          ],
        ),
      ]);
      final s = await b.stream.firstWhere(
        (s) => s.pinnedStopsRemaining != null,
      );
      expect(s.pinnedStopsRemaining, 3);
      expect(channel.last?.remainingStops, 3);
      expect(channel.last?.plate, 'KKA-1288');
      expect(channel.last?.routeNumber, '307');
      await b.close();
    },
  );

  test('unpinned waiting session never subscribes to route ETA', () async {
    final channel = _CapturingChannel();
    final b = bloc(channel: channel)..add(JourneyStarted(legs: [_leg()]));
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.waiting);
    await Future<void>.delayed(Duration.zero);
    expect(routeEtaCtrl.hasListener, isFalse);
    expect(b.state.pinnedStopsRemaining, isNull);
    expect(channel.last?.remainingStops, isNull);
    expect(channel.last?.plate, isNull);
    expect(channel.last?.routeNumber, '307');
    await b.close();
  });
}
