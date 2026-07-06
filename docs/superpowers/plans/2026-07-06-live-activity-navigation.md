# Live Activity / 動態島導航 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a user starts navigating a planned route, show live journey status (next departure ETA while waiting; vehicle/next-station while riding) on the iOS lock screen + Dynamic Island, and in an Android picture-in-picture window.

**Architecture:** One platform-agnostic `JourneySessionBloc` owns the navigation session state machine (`waiting ⇄ riding → next leg → done`). Platform layers only render: iOS via the existing `com.jnjk.bus/live_activity` MethodChannel → ActivityKit; Android via the existing ongoing-notification plugin (kept as-is) plus a new PiP window that renders a compact Flutter card. ETA updates are local-only (no push).

**Tech Stack:** Flutter (flutter_bloc, geolocator — both already installed), Swift ActivityKit (existing extension `app/ios/BusLiveActivity/`), Kotlin (existing `LiveActivityPlugin.kt` + new PiP hooks). **No new dependencies.**

**Spec:** `docs/superpowers/specs/2026-07-06-live-activity-navigation-design.md`

## Global Constraints

- No new pub/CocoaPods/Gradle dependencies.
- Never hand-edit generated files; no proto changes are needed in this plan.
- Flutter analyze must stay clean (`--no-fatal-infos` gates warnings): run `flutter analyze` before every commit.
- Design rules (docs/design.md): all time values in JetBrainsMono (Flutter) / `.monospacedDigit()` (Swift); static emphasis only, never pulsing; Ink `#111111` is the only UI accent.
- Bloc only, no Cubit. Tests use plain `flutter_test` (no bloc_test package).
- Comments: neutral labels, only for non-obvious constraints.
- All user-facing copy in 繁體中文 (existing style: 「下一站 X」).
- Existing MethodChannel name `com.jnjk.bus/live_activity` and methods `start`/`update`/`stop` must keep working on both platforms.
- Commits stay in the isolated worktree; merging to the user's branch requires user approval.
- `git add` only the files the task modified, as explicit paths — never `git add -A` / `git add .` / `git add -u`.

---

### Task 1: Journey models + leg mapping

**Files:**
- Modify: `app/lib/data/models/plan_models.dart` (add `PlanIdentity`, expose it on `PlanSection`)
- Create: `app/lib/features/live_activity/model/journey_models.dart`
- Test: `app/test/features/live_activity/journey_models_test.dart`

**Interfaces:**
- Consumes: `PlanRoute`/`PlanSection` from `plan_models.dart`; proto `maas.NotificationIdentity` (already in `maas.pb.dart`: fields `routeType`, `routeKey`, `direction`, `departureStopKey`, `arrivalStopKey`, `supported`).
- Produces: `JourneyLeg.legsFromRoute(PlanRoute) → List<JourneyLeg>`, `enum JourneyLegKind { bus, metro, tra, thsr, other }`, `class JourneyLeg` with fields listed below. Task 3's bloc and Task 2's channel payloads are built from these.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/live_activity/journey_models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

PlanSection _section({
  required String type,
  String mode = '',
  String shortName = '',
  String headsign = '',
  String depName = '起點',
  String arrName = '終點',
  String depTime = '2026-07-06T10:00:00+08:00',
  int walkSeconds = 0,
  PlanIdentity identity = const PlanIdentity.empty(),
  List<PlanStop> stops = const [],
}) {
  return PlanSection(
    type: type,
    travelSummary: PlanTravelSummary(duration: walkSeconds, length: 0),
    departure: PlanPlace(
      name: depName,
      type: 'station',
      location: const PlanPoint(lat: 25.0, lng: 121.5),
      time: depTime,
    ),
    arrival: PlanPlace(
      name: arrName,
      type: 'station',
      location: const PlanPoint(lat: 25.1, lng: 121.6),
      time: '2026-07-06T10:30:00+08:00',
    ),
    transport: PlanTransport(
      mode: mode,
      name: shortName,
      shortName: shortName,
      longName: '',
      headsign: headsign,
      category: '',
      routeColor: '',
    ),
    intermediateStops: stops,
    identity: identity,
  );
}

void main() {
  group('JourneyLeg.legsFromRoute', () {
    test('folds a leading walk into the next transit leg', () {
      final route = PlanRoute(
        travelTime: 1800,
        startTime: '2026-07-06T09:55:00+08:00',
        endTime: '2026-07-06T10:30:00+08:00',
        transfers: 0,
        sections: [
          _section(type: 'pedestrian', walkSeconds: 300),
          _section(
            type: 'transit',
            mode: 'bus',
            shortName: '307',
            headsign: '板橋',
            identity: const PlanIdentity(
              routeType: 'bus',
              routeKey: 'TPE307',
              direction: '0',
              departureStopKey: 'Taipei:STOP1',
              arrivalStopKey: 'Taipei:STOP9',
              supported: true,
            ),
          ),
        ],
      );

      final legs = JourneyLeg.legsFromRoute(route);
      expect(legs, hasLength(1));
      expect(legs.first.kind, JourneyLegKind.bus);
      expect(legs.first.routeLabel, '307 往板橋');
      expect(legs.first.leadingWalkMinutes, 5);
      expect(legs.first.boardStop, '起點');
      expect(legs.first.identity.supported, isTrue);
      expect(legs.first.scheduledDeparture, isNotNull);
    });

    test('maps rail modes and keeps stop names for progress', () {
      final route = PlanRoute(
        travelTime: 3600,
        startTime: '',
        endTime: '',
        transfers: 1,
        sections: [
          _section(
            type: 'transit',
            mode: 'train',
            shortName: '自強123',
            identity: const PlanIdentity(
              routeType: 'tra',
              routeKey: '123',
              direction: '0',
              departureStopKey: '1000',
              arrivalStopKey: '3300',
              supported: false,
            ),
            stops: const [
              PlanStop(
                name: '中壢',
                location: PlanPoint(lat: 24.9, lng: 121.2),
                departureTime: '',
              ),
            ],
          ),
          _section(
            type: 'transit',
            mode: 'subway',
            shortName: '板南線',
            identity: const PlanIdentity(
              routeType: 'mrt',
              routeKey: 'TRTC:BL',
              direction: '0',
              departureStopKey: 'BL12',
              arrivalStopKey: 'BL15',
              supported: false,
            ),
          ),
        ],
      );

      final legs = JourneyLeg.legsFromRoute(route);
      expect(legs, hasLength(2));
      expect(legs[0].kind, JourneyLegKind.tra);
      expect(legs[0].stopNames, ['中壢']);
      expect(legs[1].kind, JourneyLegKind.metro);
      expect(legs[1].leadingWalkMinutes, 0);
    });

    test('walking-only route yields no legs', () {
      final route = PlanRoute(
        travelTime: 600,
        startTime: '',
        endTime: '',
        transfers: 0,
        sections: [_section(type: 'pedestrian', walkSeconds: 600)],
      );
      expect(JourneyLeg.legsFromRoute(route), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/features/live_activity/journey_models_test.dart`
Expected: FAIL — `PlanIdentity` / `journey_models.dart` not found.

- [ ] **Step 3: Implement**

In `plan_models.dart`, add (and add `identity` to `PlanSection`'s constructor, `fromProto`, and `props`; `fromProto` reads `proto.notificationIdentity`):

```dart
class PlanIdentity extends Equatable {
  const PlanIdentity({
    required this.routeType,
    required this.routeKey,
    required this.direction,
    required this.departureStopKey,
    required this.arrivalStopKey,
    required this.supported,
  });

  const PlanIdentity.empty()
    : routeType = '',
      routeKey = '',
      direction = '',
      departureStopKey = '',
      arrivalStopKey = '',
      supported = false;

  factory PlanIdentity.fromProto(maas.NotificationIdentity proto) =>
      PlanIdentity(
        routeType: proto.routeType,
        routeKey: proto.routeKey,
        direction: proto.direction,
        departureStopKey: proto.departureStopKey,
        arrivalStopKey: proto.arrivalStopKey,
        supported: proto.supported,
      );

  final String routeType;
  final String routeKey;
  final String direction;
  final String departureStopKey;
  final String arrivalStopKey;
  final bool supported;

  @override
  List<Object?> get props =>
      [routeType, routeKey, direction, departureStopKey, arrivalStopKey, supported];
}
```

Give `PlanSection.identity` a default of `const PlanIdentity.empty()` so existing constructions keep compiling.

Create `journey_models.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';

enum JourneyLegKind { bus, metro, tra, thsr, other }

JourneyLegKind _kindOf(PlanSection s) => switch (s.identity.routeType) {
  'bus' => JourneyLegKind.bus,
  'mrt' => JourneyLegKind.metro,
  'tra' => JourneyLegKind.tra,
  'thsr' => JourneyLegKind.thsr,
  _ => switch (s.transport.mode) {
    'bus' => JourneyLegKind.bus,
    'subway' || 'metro' => JourneyLegKind.metro,
    'train' || 'rail' => JourneyLegKind.tra,
    'highSpeedTrain' => JourneyLegKind.thsr,
    _ => JourneyLegKind.other,
  },
};

/// One transit leg of a navigation session. Leading walk sections are folded
/// into the following transit leg (walkers see 「步行至X」 inside the waiting
/// card, matching the Google Maps pattern) so the session state machine only
/// ever points at a transit leg.
class JourneyLeg extends Equatable {
  const JourneyLeg({
    required this.kind,
    required this.routeLabel,
    required this.boardStop,
    required this.alightStop,
    required this.stopNames,
    required this.identity,
    required this.leadingWalkMinutes,
    required this.scheduledDeparture,
    required this.scheduledArrival,
    required this.boardLocation,
    required this.stopLocations,
  });

  static List<JourneyLeg> legsFromRoute(PlanRoute route) {
    final legs = <JourneyLeg>[];
    var pendingWalkSeconds = 0;
    for (final section in route.sections) {
      if (section.type != 'transit') {
        pendingWalkSeconds += section.travelSummary.duration;
        continue;
      }
      final headsign = section.transport.headsign;
      final label = section.transport.shortName.isEmpty
          ? section.transport.name
          : section.transport.shortName;
      legs.add(
        JourneyLeg(
          kind: _kindOf(section),
          routeLabel: headsign.isEmpty ? label : '$label 往$headsign',
          boardStop: section.departure.name,
          alightStop: section.arrival.name,
          stopNames: [for (final s in section.intermediateStops) s.name],
          identity: section.identity,
          leadingWalkMinutes: (pendingWalkSeconds / 60).ceil(),
          scheduledDeparture: DateTime.tryParse(section.departure.time),
          scheduledArrival: DateTime.tryParse(section.arrival.time),
          boardLocation: section.departure.location,
          stopLocations: [
            for (final s in section.intermediateStops) s.location,
            section.arrival.location,
          ],
        ),
      );
      pendingWalkSeconds = 0;
    }
    return legs;
  }

  final JourneyLegKind kind;
  final String routeLabel;
  final String boardStop;
  final String alightStop;
  final List<String> stopNames;
  final PlanIdentity identity;
  final int leadingWalkMinutes;
  final DateTime? scheduledDeparture;
  final DateTime? scheduledArrival;
  final PlanPoint boardLocation;

  /// Intermediate stop locations plus the arrival location, in travel order —
  /// used for riding-mode progress by nearest-upcoming-stop.
  final List<PlanPoint> stopLocations;

  @override
  List<Object?> get props => [
    kind, routeLabel, boardStop, alightStop, stopNames, identity,
    leadingWalkMinutes, scheduledDeparture, scheduledArrival,
    boardLocation, stopLocations,
  ];
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/features/live_activity/journey_models_test.dart && flutter analyze`
Expected: PASS, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add app/lib/data/models/plan_models.dart app/lib/features/live_activity/model/journey_models.dart app/test/features/live_activity/journey_models_test.dart
git commit -m "feat: journey leg model with walk folding for live activity navigation"
```

---

### Task 2: Dart Live Activity channel wrapper

**Files:**
- Create: `app/lib/core/live_activity/live_activity_channel.dart`
- Test: `app/test/core/live_activity/live_activity_channel_test.dart`

**Interfaces:**
- Produces: `class LiveActivityChannel` with `Future<void> start(LiveActivityContent c)`, `Future<void> update(LiveActivityContent c)`, `Future<void> stop()`, and `class LiveActivityContent` with `Map<String, Object?> toArgs()`. Task 3's bloc calls these; Tasks 4–5 consume the arg keys.
- Arg keys (superset; both platforms ignore unknown keys): `mode` (`'waiting'`|`'riding'`), `type` (`'bus'|'mrt'|'tra'|'thsr'`), `routeOrTrain`, `fromStation`, `nextStation`, `previousStation`, `alightStation`, `remainingStops` (int), `progressPercent` (double 0–1), `etaMs` (int epoch ms), `arrivalTimeMs` (int, legacy alias of `etaMs`), `walkMinutes` (int).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/core/live_activity/live_activity_channel_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/live_activity/live_activity_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.jnjk.bus/live_activity');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'start' ? 'activity-1' : null;
        });
  });

  const content = LiveActivityContent(
    mode: 'waiting',
    type: 'bus',
    routeOrTrain: '307 往板橋',
    fromStation: '台北車站',
    nextStation: '台北車站',
    etaMs: 1234567890000,
    walkMinutes: 5,
  );

  test('start sends full arg map with legacy alias', () async {
    final la = LiveActivityChannel();
    await la.start(content);
    expect(calls.single.method, 'start');
    final args = Map<String, Object?>.from(calls.single.arguments as Map);
    expect(args['mode'], 'waiting');
    expect(args['etaMs'], 1234567890000);
    expect(args['arrivalTimeMs'], 1234567890000);
    expect(args['progressPercent'], 0.0);
  });

  test('update after start, stop clears', () async {
    final la = LiveActivityChannel();
    await la.start(content);
    await la.update(content);
    await la.stop();
    expect(calls.map((c) => c.method), ['start', 'update', 'stop']);
  });

  test('platform errors are swallowed — navigation must not crash', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'LA_START_FAILED');
        });
    final la = LiveActivityChannel();
    await la.start(content); // must not throw
    await la.stop();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/core/live_activity/live_activity_channel_test.dart`
Expected: FAIL — file not found.

- [ ] **Step 3: Implement**

```dart
// app/lib/core/live_activity/live_activity_channel.dart
import 'package:flutter/services.dart';

class LiveActivityContent {
  const LiveActivityContent({
    required this.mode,
    required this.type,
    required this.routeOrTrain,
    required this.fromStation,
    required this.nextStation,
    this.previousStation,
    this.alightStation,
    this.remainingStops,
    this.progressPercent = 0.0,
    this.etaMs,
    this.walkMinutes = 0,
  });

  final String mode;
  final String type;
  final String routeOrTrain;
  final String fromStation;
  final String nextStation;
  final String? previousStation;
  final String? alightStation;
  final int? remainingStops;
  final double progressPercent;
  final int? etaMs;
  final int walkMinutes;

  Map<String, Object?> toArgs() => {
    'mode': mode,
    'type': type,
    'routeOrTrain': routeOrTrain,
    'fromStation': fromStation,
    'nextStation': nextStation,
    'previousStation': previousStation,
    'alightStation': alightStation,
    'remainingStops': remainingStops,
    'progressPercent': progressPercent,
    'etaMs': etaMs,
    // Legacy key: shipped Swift/Kotlin readers predate `etaMs`.
    'arrivalTimeMs': etaMs,
    'walkMinutes': walkMinutes,
  };
}

/// Thin wrapper over the platform live-activity channel. All platform errors
/// are swallowed: a broken lock-screen card must never break navigation.
class LiveActivityChannel {
  static const _channel = MethodChannel('com.jnjk.bus/live_activity');
  bool _active = false;

  Future<void> start(LiveActivityContent content) async {
    try {
      await _channel.invokeMethod<String>('start', content.toArgs());
      _active = true;
    } on PlatformException {
      _active = false;
    } on MissingPluginException {
      _active = false;
    }
  }

  Future<void> update(LiveActivityContent content) async {
    if (!_active) return;
    try {
      await _channel.invokeMethod<void>('update', content.toArgs());
    } on PlatformException {
      // keep session alive; next update retries
    } on MissingPluginException {
      _active = false;
    }
  }

  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // already gone — nothing to clean up
    } on MissingPluginException {
      // no-op
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/core/live_activity/ && flutter analyze`
Expected: PASS, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/live_activity/ app/test/core/live_activity/
git commit -m "feat: dart wrapper for live activity platform channel"
```

---

### Task 3: JourneySessionBloc

**Files:**
- Create: `app/lib/features/live_activity/bloc/journey_session_bloc.dart`
- Create: `app/lib/features/live_activity/bloc/journey_session_event.dart`
- Create: `app/lib/features/live_activity/bloc/journey_session_state.dart`
- Create: `app/lib/features/live_activity/data/leg_eta_source.dart`
- Test: `app/test/features/live_activity/journey_session_bloc_test.dart`

**Interfaces:**
- Consumes: `JourneyLeg`, `JourneyLegKind` (Task 1); `LiveActivityChannel`, `LiveActivityContent` (Task 2); `BusStopEtaRepository.instance.watchStop(String stopId, {String? city})` → `Stream<List<BusStopArrival>>` (existing).
- Produces (used by Tasks 5–7):
  - `class JourneySessionBloc extends Bloc<JourneySessionEvent, JourneySessionState>` — constructor `JourneySessionBloc({LegEtaStream etaStream = defaultLegEtaStream, LiveActivityChannel? channel, Stream<Position> Function()? positions, Duration sessionTimeout = const Duration(hours: 8)})`
  - Events: `JourneyStarted(List<JourneyLeg> legs)`, `BoardConfirmed()`, `AlightConfirmed()`, `JourneyCancelled()`
  - State: `JourneySessionState { JourneyPhase phase; List<JourneyLeg> legs; int legIndex; Duration? eta; int nextStopIndex; bool suggestBoarding; JourneyLeg? get currentLeg; }` with `enum JourneyPhase { idle, waiting, riding, done }`
  - `typedef LegEtaStream = Stream<Duration?> Function(JourneyLeg leg)`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/features/live_activity/journey_session_bloc_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

JourneyLeg _leg(String label) => JourneyLeg(
  kind: JourneyLegKind.bus,
  routeLabel: label,
  boardStop: '起點站',
  alightStop: '終點站',
  stopNames: const ['中站'],
  identity: const PlanIdentity.empty(),
  leadingWalkMinutes: 0,
  scheduledDeparture: DateTime(2026, 7, 6, 10),
  scheduledArrival: DateTime(2026, 7, 6, 10, 30),
  boardLocation: const PlanPoint(lat: 25, lng: 121.5),
  stopLocations: const [
    PlanPoint(lat: 25.01, lng: 121.51),
    PlanPoint(lat: 25.02, lng: 121.52),
  ],
);

void main() {
  late StreamController<Duration?> etaCtrl;
  JourneySessionBloc bloc() => JourneySessionBloc(
    etaStream: (_) => etaCtrl.stream,
    channel: null, // platform channel skipped in tests
    positions: null,
  );

  setUp(() => etaCtrl = StreamController<Duration?>.broadcast());
  tearDown(() => etaCtrl.close());

  test('start → waiting on first leg with streamed ETA', () async {
    final b = bloc()..add(JourneyStarted(legs: [_leg('307')]));
    await expectLater(
      b.stream,
      emits(
        isA<JourneySessionState>()
            .having((s) => s.phase, 'phase', JourneyPhase.waiting)
            .having((s) => s.legIndex, 'legIndex', 0),
      ),
    );
    etaCtrl.add(const Duration(minutes: 3));
    await expectLater(
      b.stream,
      emits(
        isA<JourneySessionState>()
            .having((s) => s.eta, 'eta', const Duration(minutes: 3)),
      ),
    );
    await b.close();
  });

  test('board → riding; alight on last leg → done', () async {
    final b = bloc()..add(JourneyStarted(legs: [_leg('307')]));
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.waiting);
    b.add(const BoardConfirmed());
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.riding);
    b.add(const AlightConfirmed());
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.done);
    await b.close();
  });

  test('alight on non-final leg advances to waiting on next leg', () async {
    final b = bloc()
      ..add(JourneyStarted(legs: [_leg('307'), _leg('自強123')]));
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.waiting);
    b.add(const BoardConfirmed());
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.riding);
    b.add(const AlightConfirmed());
    final s = await b.stream.firstWhere(
      (s) => s.phase == JourneyPhase.waiting,
    );
    expect(s.legIndex, 1);
    expect(s.currentLeg?.routeLabel, '自強123');
    await b.close();
  });

  test('eta reaching zero flags suggestBoarding while waiting', () async {
    final b = bloc()..add(JourneyStarted(legs: [_leg('307')]));
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.waiting);
    etaCtrl.add(Duration.zero);
    final s = await b.stream.firstWhere((s) => s.eta == Duration.zero);
    expect(s.suggestBoarding, isTrue);
    await b.close();
  });

  test('cancel from any phase → done', () async {
    final b = bloc()..add(JourneyStarted(legs: [_leg('307')]));
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.waiting);
    b.add(const JourneyCancelled());
    await b.stream.firstWhere((s) => s.phase == JourneyPhase.done);
    await b.close();
  });

  test('eta stream error falls back to scheduled countdown', () async {
    final b = JourneySessionBloc(
      etaStream: (_) => Stream<Duration?>.error(Exception('grpc drop')),
      channel: null,
      positions: null,
    )..add(JourneyStarted(legs: [_leg('307')]));
    // scheduledDeparture is in the past → fallback emits Duration.zero
    final s = await b.stream.firstWhere((s) => s.eta != null);
    expect(s.eta, Duration.zero);
    await b.close();
  });

  test('empty legs list is a no-op', () async {
    final b = bloc()..add(const JourneyStarted(legs: []));
    await Future<void>.delayed(Duration.zero);
    expect(b.state.phase, JourneyPhase.idle);
    await b.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/features/live_activity/journey_session_bloc_test.dart`
Expected: FAIL — bloc files not found.

- [ ] **Step 3: Implement events + state**

```dart
// app/lib/features/live_activity/bloc/journey_session_event.dart
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

abstract class JourneySessionEvent {
  const JourneySessionEvent();
}

class JourneyStarted extends JourneySessionEvent {
  const JourneyStarted({required this.legs});
  final List<JourneyLeg> legs;
}

class BoardConfirmed extends JourneySessionEvent {
  const BoardConfirmed();
}

class AlightConfirmed extends JourneySessionEvent {
  const AlightConfirmed();
}

class JourneyCancelled extends JourneySessionEvent {
  const JourneyCancelled();
}

/// Internal: new ETA value for the current waiting leg (null = unknown).
class EtaTicked extends JourneySessionEvent {
  const EtaTicked(this.eta);
  final Duration? eta;
}

/// Internal: riding-mode progress advanced to [nextStopIndex].
class ProgressTicked extends JourneySessionEvent {
  const ProgressTicked(this.nextStopIndex);
  final int nextStopIndex;
}
```

```dart
// app/lib/features/live_activity/bloc/journey_session_state.dart
import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

enum JourneyPhase { idle, waiting, riding, done }

class JourneySessionState extends Equatable {
  const JourneySessionState({
    this.phase = JourneyPhase.idle,
    this.legs = const [],
    this.legIndex = 0,
    this.eta,
    this.nextStopIndex = 0,
    this.suggestBoarding = false,
  });

  final JourneyPhase phase;
  final List<JourneyLeg> legs;
  final int legIndex;
  final Duration? eta;
  final int nextStopIndex;
  final bool suggestBoarding;

  JourneyLeg? get currentLeg =>
      legIndex < legs.length ? legs[legIndex] : null;

  bool get isLastLeg => legIndex >= legs.length - 1;

  JourneySessionState copyWith({
    JourneyPhase? phase,
    List<JourneyLeg>? legs,
    int? legIndex,
    Duration? eta,
    bool clearEta = false,
    int? nextStopIndex,
    bool? suggestBoarding,
  }) {
    return JourneySessionState(
      phase: phase ?? this.phase,
      legs: legs ?? this.legs,
      legIndex: legIndex ?? this.legIndex,
      eta: clearEta ? null : eta ?? this.eta,
      nextStopIndex: nextStopIndex ?? this.nextStopIndex,
      suggestBoarding: suggestBoarding ?? this.suggestBoarding,
    );
  }

  @override
  List<Object?> get props =>
      [phase, legs, legIndex, eta, nextStopIndex, suggestBoarding];
}
```

- [ ] **Step 4: Implement the ETA source**

```dart
// app/lib/features/live_activity/data/leg_eta_source.dart
import 'package:wheres_the_car/data/repositories/bus_stop_eta_repository.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

typedef LegEtaStream = Stream<Duration?> Function(JourneyLeg leg);

/// Live ETA for bus legs whose notification identity resolved; every other
/// leg counts down from its scheduled departure.
// ponytail: metro/rail use scheduled countdown for now — switch to live
// sources once the planner emits supported identities for them.
Stream<Duration?> defaultLegEtaStream(JourneyLeg leg) {
  if (leg.kind == JourneyLegKind.bus && leg.identity.supported) {
    return BusStopEtaRepository.instance
        .watchStop(leg.identity.departureStopKey)
        .map((arrivals) {
          for (final a in arrivals) {
            if (leg.routeLabel.startsWith(a.routeName) &&
                a.minutes != null) {
              return Duration(minutes: a.minutes!);
            }
            if (leg.routeLabel.startsWith(a.routeName) &&
                a.state == BusArrivalState.arriving) {
              return Duration.zero;
            }
          }
          return null;
        });
  }
  return scheduledCountdown(leg.scheduledDeparture);
}

/// Emits the remaining time until [departure] once per 30s, clamped at zero.
Stream<Duration?> scheduledCountdown(
  DateTime? departure, {
  Duration tick = const Duration(seconds: 30),
}) async* {
  if (departure == null) {
    yield null;
    return;
  }
  Duration remaining() {
    final d = departure.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  yield remaining();
  yield* Stream.periodic(tick, (_) => remaining());
}
```

- [ ] **Step 5: Implement the bloc**

```dart
// app/lib/features/live_activity/bloc/journey_session_bloc.dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wheres_the_car/core/live_activity/live_activity_channel.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_car/features/live_activity/data/leg_eta_source.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

class JourneySessionBloc
    extends Bloc<JourneySessionEvent, JourneySessionState> {
  JourneySessionBloc({
    LegEtaStream etaStream = defaultLegEtaStream,
    LiveActivityChannel? channel,
    Stream<Position> Function()? positions,
    this.sessionTimeout = const Duration(hours: 8),
  }) : _etaStream = etaStream,
       _channel = channel,
       _positions = positions,
       super(const JourneySessionState()) {
    on<JourneyStarted>(_onStarted);
    on<BoardConfirmed>(_onBoarded);
    on<AlightConfirmed>(_onAlighted);
    on<JourneyCancelled>(_onCancelled);
    on<EtaTicked>(_onEta);
    on<ProgressTicked>(_onProgress);
  }

  final LegEtaStream _etaStream;
  final LiveActivityChannel? _channel;
  final Stream<Position> Function()? _positions;

  /// ActivityKit hard-caps activities at 8h; the session ends itself first.
  final Duration sessionTimeout;

  StreamSubscription<Duration?>? _etaSub;
  StreamSubscription<Position>? _posSub;
  Timer? _timeout;

  Future<void> _onStarted(
    JourneyStarted event,
    Emitter<JourneySessionState> emit,
  ) async {
    if (event.legs.isEmpty) return;
    _timeout?.cancel();
    _timeout = Timer(sessionTimeout, () => add(const JourneyCancelled()));
    emit(
      JourneySessionState(
        phase: JourneyPhase.waiting,
        legs: event.legs,
        legIndex: 0,
      ),
    );
    _subscribeEta(event.legs.first);
    await _channel?.start(_content(state));
  }

  void _onBoarded(BoardConfirmed _, Emitter<JourneySessionState> emit) {
    if (state.phase != JourneyPhase.waiting) return;
    _etaSub?.cancel();
    emit(
      state.copyWith(
        phase: JourneyPhase.riding,
        clearEta: true,
        nextStopIndex: 0,
        suggestBoarding: false,
      ),
    );
    _subscribePositions();
    unawaited(_channel?.update(_content(state)));
  }

  void _onAlighted(AlightConfirmed _, Emitter<JourneySessionState> emit) {
    if (state.phase != JourneyPhase.riding) return;
    _posSub?.cancel();
    if (state.isLastLeg) {
      _end(emit);
      return;
    }
    final next = state.legIndex + 1;
    emit(
      state.copyWith(
        phase: JourneyPhase.waiting,
        legIndex: next,
        clearEta: true,
        nextStopIndex: 0,
        suggestBoarding: false,
      ),
    );
    _subscribeEta(state.legs[next]);
    unawaited(_channel?.update(_content(state)));
  }

  void _onCancelled(JourneyCancelled _, Emitter<JourneySessionState> emit) {
    if (state.phase == JourneyPhase.idle) return;
    _end(emit);
  }

  void _onEta(EtaTicked event, Emitter<JourneySessionState> emit) {
    if (state.phase != JourneyPhase.waiting) return;
    final suggest = event.eta != null && event.eta! <= Duration.zero;
    emit(state.copyWith(eta: event.eta, suggestBoarding: suggest));
    unawaited(_channel?.update(_content(state)));
  }

  void _onProgress(ProgressTicked event, Emitter<JourneySessionState> emit) {
    if (state.phase != JourneyPhase.riding) return;
    if (event.nextStopIndex <= state.nextStopIndex) return;
    emit(state.copyWith(nextStopIndex: event.nextStopIndex));
    unawaited(_channel?.update(_content(state)));
  }

  void _end(Emitter<JourneySessionState> emit) {
    _etaSub?.cancel();
    _posSub?.cancel();
    _timeout?.cancel();
    emit(state.copyWith(phase: JourneyPhase.done, suggestBoarding: false));
    unawaited(_channel?.stop());
  }

  void _subscribeEta(JourneyLeg leg) {
    _etaSub?.cancel();
    // Stream error (gRPC drop) → fall back to the scheduled countdown, per
    // spec: never blank the card mid-journey.
    _etaSub = _etaStream(leg).listen(
      (eta) => add(EtaTicked(eta)),
      onError: (Object _) {
        _etaSub?.cancel();
        _etaSub = scheduledCountdown(leg.scheduledDeparture)
            .listen((eta) => add(EtaTicked(eta)));
      },
    );
  }

  void _subscribePositions() {
    final positions = _positions;
    if (positions == null) return;
    _posSub?.cancel();
    _posSub = positions().listen(_onPosition);
  }

  void _onPosition(Position pos) {
    final leg = state.currentLeg;
    if (leg == null || state.phase != JourneyPhase.riding) return;
    // Nearest upcoming stop wins; never move backwards (index is monotonic).
    var best = state.nextStopIndex;
    var bestDist = double.infinity;
    for (var i = state.nextStopIndex; i < leg.stopLocations.length; i++) {
      final p = leg.stopLocations[i];
      final d = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, p.lat, p.lng,
      );
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    if (best != state.nextStopIndex) add(ProgressTicked(best));
  }

  LiveActivityContent _content(JourneySessionState s) {
    final leg = s.currentLeg!;
    final total = leg.stopLocations.length;
    final names = [...leg.stopNames, leg.alightStop];
    final nextName = s.phase == JourneyPhase.riding && s.nextStopIndex < names.length
        ? names[s.nextStopIndex]
        : leg.boardStop;
    return LiveActivityContent(
      mode: s.phase == JourneyPhase.riding ? 'riding' : 'waiting',
      type: leg.kind.name == 'metro' ? 'mrt' : leg.kind.name,
      routeOrTrain: leg.routeLabel,
      fromStation: leg.boardStop,
      nextStation: nextName,
      alightStation: leg.alightStop,
      remainingStops:
          s.phase == JourneyPhase.riding ? total - s.nextStopIndex : null,
      progressPercent:
          s.phase == JourneyPhase.riding && total > 0
              ? s.nextStopIndex / total
              : 0.0,
      etaMs: s.eta == null
          ? null
          : DateTime.now().add(s.eta!).millisecondsSinceEpoch,
      walkMinutes: s.phase == JourneyPhase.waiting
          ? leg.leadingWalkMinutes
          : 0,
    );
  }

  @override
  Future<void> close() {
    _etaSub?.cancel();
    _posSub?.cancel();
    _timeout?.cancel();
    return super.close();
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd app && flutter test test/features/live_activity/ && flutter analyze`
Expected: PASS, analyze clean.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/live_activity/ app/test/features/live_activity/
git commit -m "feat: journey session bloc driving live activity updates"
```

---

### Task 4: iOS — ContentState v2 + waiting-mode UI

**Files:**
- Modify: `app/ios/BusLiveActivity/BusLiveActivityAttributes.swift`
- Modify: `app/ios/BusLiveActivity/BusLiveActivityLiveActivity.swift`
- Modify: `app/ios/Runner/LiveActivityPlugin.swift:73-81` (contentState mapping)
- Modify: `app/ios/Runner/Info.plist` (background location during navigation)

**Interfaces:**
- Consumes: channel args from Task 2 (`mode`, `vehicleNo` omitted — `routeOrTrain` covers it, `alightStation`, `remainingStops`, `etaMs`, `walkMinutes`).
- Produces: nothing consumed by later tasks; pure render layer.

- [ ] **Step 1: Extend ContentState**

Replace `BusLiveActivityAttributes.swift` body:

```swift
import ActivityKit
import Foundation

struct BusLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "waiting" | "riding"
        var mode: String
        var nextStation: String
        var previousStation: String?
        var alightStation: String?
        var remainingStops: Int?
        var progressPercent: Double
        /// waiting: expected departure; riding: expected arrival
        var etaDate: Date?
        var walkMinutes: Int
    }

    let routeOrTrain: String
    let fromStation: String
    let toStation: String
    let type: String
}
```

- [ ] **Step 2: Update the plugin mapping**

In `LiveActivityPlugin.swift`, replace `contentState(from:)`:

```swift
@available(iOS 16.1, *)
private func contentState(from args: [String: Any]) -> BusLiveActivityAttributes.ContentState {
    let ms = (args["etaMs"] as? Int) ?? (args["arrivalTimeMs"] as? Int) ?? 0
    return BusLiveActivityAttributes.ContentState(
        mode: args["mode"] as? String ?? "riding",
        nextStation: args["nextStation"] as? String ?? "",
        previousStation: args["previousStation"] as? String,
        alightStation: args["alightStation"] as? String,
        remainingStops: args["remainingStops"] as? Int,
        progressPercent: args["progressPercent"] as? Double ?? 0.0,
        etaDate: ms > 0 ? Date(timeIntervalSince1970: Double(ms) / 1000) : nil,
        walkMinutes: args["walkMinutes"] as? Int ?? 0
    )
}
```

Also in `startActivity`, map `routeOrTrain`/`fromStation` as today but set `toStation: args["alightStation"] as? String ?? ""`.

- [ ] **Step 3: Widget UI — waiting mode with self-ticking countdown**

In `BusLiveActivityLiveActivity.swift`, keep the existing riding layout and branch on mode. Lock-screen body becomes:

```swift
ActivityConfiguration(for: BusLiveActivityAttributes.self) { context in
    if context.state.mode == "waiting" {
        WaitingCard(context: context)
    } else {
        RidingCard(context: context) // extract today's HStack into RidingCard
    }
} dynamicIsland: { context in
    // compactLeading: waiting → "下一班 307"; riding → "下一站 X"
    // compactTrailing: waiting → countdown; riding → circular progress
    ...
}
```

`WaitingCard` (new struct in the same file):

```swift
@available(iOS 16.1, *)
private struct WaitingCard: View {
    let context: ActivityViewContext<BusLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.wave")
                .font(.system(size: 40))
            VStack(alignment: .leading, spacing: 4) {
                Text("下一班 \(context.attributes.routeOrTrain)")
                    .font(.system(size: 16, weight: .semibold))
                Text("於 \(context.attributes.fromStation) 上車")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                if context.state.walkMinutes > 0 {
                    Text("步行 \(context.state.walkMinutes) 分至上車站")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if let eta = context.state.etaDate, eta > Date() {
                // Self-ticking: no channel update needed per second.
                Text(timerInterval: Date()...eta, countsDown: true)
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 72)
            } else {
                Text("進站中")
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .padding(16)
    }
}
```

Dynamic Island: `compactLeading` shows `mode == "waiting" ? "下一班 \(routeOrTrain)" : "下一站 \(nextStation)"`; `compactTrailing` shows `Text(timerInterval:)` (waiting, `.monospacedDigit()`, `.frame(maxWidth: 44)`) or the existing `_CircularProgress` (riding). Expanded bottom in riding mode adds a line `「\(alightStation ?? "") 下車・剩 \(remainingStops ?? 0) 站」`.

- [ ] **Step 4: Background location**

In `app/ios/Runner/Info.plist` add (if not present):

```xml
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
```

- [ ] **Step 5: Build check + commit**

Run: `cd app && flutter build ios --config-only --dart-define-from-file=env/test.json && xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'generic/platform=iOS Simulator' build | tail -5`
Expected: BUILD SUCCEEDED. (If no signing available, `xcodebuild ... CODE_SIGNING_ALLOWED=NO`.)

```bash
git add app/ios/
git commit -m "feat: waiting-mode live activity UI with self-ticking countdown"
```

Manual verification (deferred to final checklist): lock screen waiting→riding, Dynamic Island compact/expanded.

---

### Task 5: Android — PiP window

**Files:**
- Modify: `app/android/app/src/main/AndroidManifest.xml` (MainActivity attrs)
- Modify: `app/android/app/src/main/kotlin/com/example/bus/MainActivity.kt`
- Create: `app/lib/core/live_activity/pip_mode.dart`
- Create: `app/lib/features/live_activity/view/journey_pip_card.dart`
- Modify: `app/lib/app/app.dart` (builder wrap + global `JourneySessionBloc` provider)
- Test: `app/test/features/live_activity/journey_pip_card_test.dart`

**Interfaces:**
- Consumes: `JourneySessionBloc`/`JourneySessionState` (Task 3).
- Produces: channel `com.jnjk.bus/pip` — Dart→native `setNavigating(bool)`; native→Dart method `pipChanged` with bool arg. `PipMode.instance.isPip: ValueNotifier<bool>`, `PipMode.instance.setNavigating(bool)`.

- [ ] **Step 1: Manifest**

On the `<activity android:name=".MainActivity"` element add:

```xml
android:supportsPictureInPicture="true"
```

and ensure `android:configChanges` contains `screenSize|smallestScreenSize|screenLayout|orientation` (append missing values to the existing attribute).

- [ ] **Step 2: MainActivity PiP hooks**

```kotlin
// additions to MainActivity.kt
import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.util.Rational
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var navigating = false
    private var pipChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureFcmChannel()
        LiveActivityPlugin(this).register(flutterEngine.dartExecutor.binaryMessenger)
        pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.jnjk.bus/pip",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setNavigating" -> {
                        navigating = call.arguments as? Boolean ?: false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (navigating && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            enterPictureInPictureMode(
                PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(2, 1))
                    .build(),
            )
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
```

- [ ] **Step 3: Dart PiP listener**

```dart
// app/lib/core/live_activity/pip_mode.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android picture-in-picture bridge. iOS: both methods are no-ops
/// (MissingPluginException swallowed) and [isPip] stays false.
class PipMode {
  PipMode._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        isPip.value = call.arguments as bool? ?? false;
      }
    });
  }

  static final PipMode instance = PipMode._();
  static const _channel = MethodChannel('com.jnjk.bus/pip');

  final ValueNotifier<bool> isPip = ValueNotifier(false);

  Future<void> setNavigating(bool value) async {
    try {
      await _channel.invokeMethod<void>('setNavigating', value);
    } on MissingPluginException {
      // iOS / tests
    }
  }
}
```

- [ ] **Step 4: Write the failing card test**

```dart
// app/test/features/live_activity/journey_pip_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/view/journey_pip_card.dart';
import 'journey_models_test.dart' show buildTestLeg; // export a builder from Task 1's test, or duplicate the helper here

void main() {
  testWidgets('waiting mode shows route and board stop', (tester) async {
    final bloc = JourneySessionBloc(
      etaStream: (_) => const Stream.empty(),
      channel: null,
      positions: null,
    )..add(JourneyStarted(legs: [buildTestLeg('307 往板橋')]));
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: bloc, child: const JourneyPipCard()),
      ),
    );
    await tester.pump();
    expect(find.textContaining('307 往板橋'), findsOneWidget);
    expect(find.textContaining('起點站'), findsOneWidget);
    await bloc.close();
  });
}
```

(If importing a helper across test files is awkward, duplicate the `_leg` builder — 20 lines beats a shared fixtures file.)

- [ ] **Step 5: Implement the card**

```dart
// app/lib/features/live_activity/view/journey_pip_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_state.dart';

/// Compact card rendered as the whole UI while Android PiP is active.
class JourneyPipCard extends StatelessWidget {
  const JourneyPipCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<JourneySessionBloc>().state;
    final leg = s.currentLeg;
    if (leg == null) return const SizedBox.shrink();
    final waiting = s.phase == JourneyPhase.waiting;
    final names = [...leg.stopNames, leg.alightStop];
    final nextName = !waiting && s.nextStopIndex < names.length
        ? names[s.nextStopIndex]
        : leg.boardStop;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              waiting ? '下一班 ${leg.routeLabel}' : leg.routeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    waiting ? '於 $nextName 上車' : '下一站 $nextName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (waiting && s.eta != null)
                  Text(
                    '${s.eta!.inMinutes}分',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'JetBrainsMono',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Wire into app.dart**

In `app/lib/app/app.dart`: add `BlocProvider(create: (_) => JourneySessionBloc(), lazy: true)` next to the existing `AlertBloc` provider, and in `MaterialApp.router`'s `builder`, wrap the existing child:

```dart
builder: (context, child) => ValueListenableBuilder<bool>(
  valueListenable: PipMode.instance.isPip,
  builder: (context, pip, _) =>
      pip ? const JourneyPipCard() : (child ?? const SizedBox.shrink()),
),
```

(Compose with any existing builder content rather than replacing it.)

- [ ] **Step 7: Run tests + commit**

Run: `cd app && flutter test test/features/live_activity/ && flutter analyze`
Expected: PASS, analyze clean.

```bash
git add app/android/ app/lib/core/live_activity/pip_mode.dart app/lib/features/live_activity/view/ app/lib/app/app.dart app/test/features/live_activity/journey_pip_card_test.dart
git commit -m "feat: android pip window for journey navigation"
```

---

### Task 6: go feature integration (start/board/alight/end)

**Files:**
- Modify: `app/lib/features/go/view/go_screen.dart` (navigation start ~line 123, end)
- Modify: `app/lib/features/go/widgets/go_navigation_widgets.dart` (board/alight controls, suggest banner)
- Test: extend `app/test/features/go/` with a bloc-level wiring test if one exists; otherwise widget test for the controls.

**Interfaces:**
- Consumes: `PlanBloc` state (`result`, `selectedRouteIndex`), `JourneySessionBloc` (Task 3), `JourneyLeg.legsFromRoute` (Task 1), `PipMode.instance.setNavigating` (Task 5), `HiveStore` `live_activity_enabled` getter (existing, `app/lib/core/storage/hive_store.dart:49`).
- Produces: user-visible controls; no downstream code consumers.

- [ ] **Step 1: Start navigation**

Where `NavigationStarted` is dispatched (`go_screen.dart:123`), also:

```dart
final route = planState.result!.routes[planState.selectedRouteIndex!];
final legs = JourneyLeg.legsFromRoute(route);
if (legs.isNotEmpty && HiveStore.instance.liveActivityEnabled) {
  context.read<JourneySessionBloc>().add(JourneyStarted(legs: legs));
  PipMode.instance.setNavigating(true);
}
```

(Use the actual getter name from hive_store.dart — read it first; line 49 defines it.)

- [ ] **Step 2: End navigation**

Where `NavigationEnded` is dispatched, also:

```dart
context.read<JourneySessionBloc>().add(const JourneyCancelled());
PipMode.instance.setNavigating(false);
```

Also listen for the session reaching `JourneyPhase.done` (e.g. `BlocListener<JourneySessionBloc, JourneySessionState>`) to call `PipMode.instance.setNavigating(false)` when the journey finishes on its own.

- [ ] **Step 3: Board/alight controls + suggest banner**

In `go_navigation_widgets.dart`, inside the active-navigation panel add a `BlocBuilder<JourneySessionBloc, JourneySessionState>`:

- `phase == waiting` → primary button 「我上車了」 → `BoardConfirmed()`; when `suggestBoarding` is true, show a static banner 「車來了——上車了嗎？」 above the button (accent `#111111`, no animation) and fire one `HapticFeedback.mediumImpact()` on the false→true transition (guard with a `BlocListener` `listenWhen`).
- `phase == riding` → primary button 「我下車了」 → `AlightConfirmed()`; caption shows 「於 {alightStop} 下車・剩 {remainingStops} 站」.
- `phase == done` → panel reverts to the non-navigating layout (dispatch `NavigationEnded` to `PlanBloc` if not already).

Follow the visual style of the surrounding widgets in that file (it already exists — match it, don't invent).

- [ ] **Step 4: Widget test**

```dart
// app/test/features/go/navigation_controls_test.dart — structure:
// pump the navigation panel with a JourneySessionBloc in waiting phase
// (etaStream: (_) => Stream.value(Duration.zero)) and assert:
//   1. 「我上車了」 button visible; suggest banner visible when eta == 0
//   2. tapping it moves the bloc to riding and shows 「我下車了」
```

Write the full test against the real widget names once Step 3 exists; assert via `find.text` and `bloc.state.phase`.

- [ ] **Step 5: Run tests + commit**

Run: `cd app && flutter test && flutter analyze`
Expected: PASS (whole suite — this task touches shared screens).

```bash
git add app/lib/features/go/ app/test/features/go/
git commit -m "feat: wire journey session into go navigation flow"
```

---

### Task 7: Background location during navigation

**Files:**
- Modify: `app/lib/core/location/location_service.dart` (navigation-grade stream)
- Modify: `app/lib/features/live_activity/bloc/journey_session_bloc.dart` (default `positions`)
- Test: covered by Task 3's injected-stream tests; add one test that the default constructor doesn't subscribe until riding.

**Interfaces:**
- Produces: `LocationService.navigationStream() → Stream<Position>`.

- [ ] **Step 1: Add navigation stream**

In `location_service.dart`:

```dart
/// Higher-accuracy stream for active navigation. iOS continues in the
/// background (UIBackgroundModes location) with the system indicator shown;
/// stops when the subscription is cancelled at journey end.
Stream<Position> navigationStream() {
  late final LocationSettings settings;
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    settings = AppleSettings(
      accuracy: LocationAccuracy.best,
      activityType: ActivityType.otherNavigation,
      distanceFilter: 25,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    );
  } else {
    settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 25,
    );
  }
  return Geolocator.getPositionStream(locationSettings: settings);
}
```

(Import `package:flutter/foundation.dart` for `defaultTargetPlatform`.)

- [ ] **Step 2: Wire at the construction site (NOT as a constructor default)**

Keep the `positions` constructor default as `null` — Task 3's tests rely on omission meaning "no position tracking"; changing the default would leak the real device stream into them. Instead, pass the real stream where the app constructs the bloc, in `app.dart`'s provider:

```dart
BlocProvider(
  create: (_) => JourneySessionBloc(
    channel: LiveActivityChannel(),
    positions: LocationService.instance.navigationStream,
  ),
  lazy: true,
),
```

Position stream errors (permission denied mid-ride) must be caught in `_subscribePositions` with `onError: (_) {}` — riding continues on manual control.

- [ ] **Step 3: Run all tests + commit**

Run: `cd app && flutter test && flutter analyze`
Expected: PASS.

```bash
git add app/lib/core/location/location_service.dart app/lib/features/live_activity/bloc/journey_session_bloc.dart
git commit -m "feat: background-capable navigation location stream"
```

---

### Task 7b: 導航自動定位 user setting

**Files:**
- Modify: `app/lib/core/storage/hive_store.dart` (new setting, next to `live_activity_enabled`)
- Modify: `app/lib/app/app.dart` (gate the positions callback)
- Modify: the settings screen under `app/lib/features/settings/` (new toggle, follow the existing `live_activity_enabled` toggle's pattern and placement)
- Test: extend `app/test/features/live_activity/` with a gate test

**Interfaces:**
- Consumes: `HiveStore` settings-box pattern; Task 7's `positions:` wiring in app.dart.
- Produces: `HiveStore.navigationLocationEnabled` (get/set, default `true`).

- [ ] **Step 1: HiveStore setting**

Follow the exact pattern of `live_activity_enabled` (hive_store.dart:49): getter `navigationLocationEnabled` reading key `'navigation_location_enabled'` with `defaultValue: true`, and the matching setter.

- [ ] **Step 2: Gate the stream at the call site**

In app.dart's provider, wrap the positions callback so the toggle is read at board time (runtime-effective, not construction-time):

```dart
positions: () => HiveStore.navigationLocationEnabled
    ? LocationService.instance.navigationStream()
    : const Stream<Position>.empty(),
```

(Import geolocator's Position where needed. An empty stream keeps the bloc's riding phase fully manual.)

- [ ] **Step 3: Settings toggle**

Add a SwitchListTile-equivalent in the settings screen next to the Live Activity toggle: title 「導航自動定位」, subtitle 「用於自動上車提醒與車上進度；關閉後導航仍可手動操作」. Match the surrounding widgets' style exactly. Static, no animation beyond the switch's own.

- [ ] **Step 4: Test**

Bloc-level test: with a positions factory that returns an erroring/marker stream only when a bool flag is true, assert the flag=false path never subscribes (mirror the existing "no positions" test pattern). Settings persistence: one HiveStore unit test if a pattern for that exists; otherwise the getter default is covered implicitly.

- [ ] **Step 5: Verify + commit**

Run: `cd app && flutter test && flutter analyze` (clean, no new info lints).

```bash
git add app/lib/core/storage/hive_store.dart app/lib/app/app.dart app/lib/features/settings/<changed file> app/test/features/live_activity/<changed test>
git commit -m "feat: user setting to control navigation auto-location"
```

---

### Task 8: Full verification + manual checklist

- [ ] **Step 1: Full suite**

Run from repo root: `make test-flutter`
Expected: PASS (regenerates proto stubs first — required because Task 1 reads `notificationIdentity` from `maas.pb.dart`).

- [ ] **Step 2: Manual device checklist (document results in the PR/report)**

On an iOS 16.1+ device or simulator (`make -C .. run-test` from `app/`):
1. Plan a route with ≥1 transit leg → 開始導航 → lock screen shows waiting card with ticking countdown; Dynamic Island compact shows 「下一班」+ countdown.
2. Tap 我上車了 → card and island switch to riding (下一站/進度/下車站).
3. Transfer route: 我下車了 on leg 1 → waiting card for leg 2.
4. 結束導航 / journey done → activity dismissed.
5. Settings `live_activity_enabled` off → no activity starts.

On Android (API 26+):
6. Start navigation → press Home → PiP window shows compact card; countdown value updates; expand → full app restored.
7. NO ongoing notification appears (PiP only, per spec 決策 3).

- [ ] **Step 3: Commit any fixes, final report**

List files changed, test output, and any checklist items that could not be run in the execution environment (no simulator/device) — flag those explicitly for the user.
