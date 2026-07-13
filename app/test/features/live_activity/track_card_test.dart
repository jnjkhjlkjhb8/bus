import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';
import 'package:wheres_the_car/features/live_activity/model/track_card.dart';

JourneyLeg _buildLeg({
  required List<PlanPoint> stopLocations,
  String alightStop = '台北車站',
  String routeLabel = '299 往板橋',
}) => JourneyLeg(
  kind: JourneyLegKind.bus,
  routeLabel: routeLabel,
  boardStop: '起站',
  alightStop: alightStop,
  stopNames: const [],
  identity: const PlanIdentity.empty(),
  leadingWalkMinutes: 0,
  scheduledDeparture: null,
  scheduledArrival: null,
  boardLocation: const PlanPoint(lat: 0, lng: 0),
  stopLocations: stopLocations,
);

void main() {
  group('TrackCard.fromRidingLeg', () {
    test('computes stopsRemaining/progress/targetStopName from leg', () {
      final leg = _buildLeg(
        stopLocations: const [
          PlanPoint(lat: 1, lng: 1),
          PlanPoint(lat: 2, lng: 2),
          PlanPoint(lat: 3, lng: 3),
          PlanPoint(lat: 4, lng: 4),
          PlanPoint(lat: 5, lng: 5),
        ],
      );

      final card = TrackCard.fromRidingLeg(
        leg,
        nextStopIndex: 2,
        etaSeconds: 90,
      );

      expect(card.routeLabel, '299 往板橋');
      expect(card.plate, isNull);
      expect(card.targetStopName, '台北車站');
      expect(card.stopsRemaining, 3);
      expect(card.progress, closeTo(0.4, 1e-9));
      expect(card.etaSeconds, 90);
    });

    test('guards against divide-by-zero with empty stopLocations', () {
      final leg = _buildLeg(stopLocations: const []);

      final card = TrackCard.fromRidingLeg(leg, nextStopIndex: 0);

      expect(card.progress, 0.0);
      expect(card.stopsRemaining, 0);
      expect(card.etaSeconds, isNull);
    });

    test('clamps stopsRemaining and progress when nextStopIndex overruns', () {
      final leg = _buildLeg(
        stopLocations: const [
          PlanPoint(lat: 1, lng: 1),
          PlanPoint(lat: 2, lng: 2),
        ],
      );

      final card = TrackCard.fromRidingLeg(leg, nextStopIndex: 5);

      expect(card.stopsRemaining, 0);
      expect(card.progress, 1.0);
    });
  });

  group('TrackCard.pinned', () {
    test('carries the plate and provided fields as-is', () {
      const card = TrackCard.pinned(
        routeLabel: '299',
        plate: 'ABC-1234',
        targetStopName: '台北車站',
        stopsRemaining: 4,
        etaSeconds: 120,
        progress: 0.25,
      );

      expect(card.routeLabel, '299');
      expect(card.plate, 'ABC-1234');
      expect(card.targetStopName, '台北車站');
      expect(card.stopsRemaining, 4);
      expect(card.etaSeconds, 120);
      expect(card.progress, 0.25);
    });
  });
}
