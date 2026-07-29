import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/data/models/plan_models.dart';

PlanPlace place(double lat, double lng) => PlanPlace(
  name: 'p',
  type: 'place',
  location: PlanPoint(lat: lat, lng: lng),
  time: '',
);

PlanSection section(
  PlanPlace from,
  PlanPlace to, {
  List<PlanStop> stops = const [],
}) => PlanSection(
  type: 'transit',
  travelSummary: const PlanTravelSummary(duration: 60, length: 100),
  departure: from,
  arrival: to,
  transport: const PlanTransport(
    mode: 'bus',
    name: '',
    shortName: '',
    longName: '',
    headsign: '',
    category: '',
    routeColor: '',
  ),
  intermediateStops: stops,
);

PlanRoute route(List<PlanSection> sections) => PlanRoute(
  travelTime: 600,
  startTime: '08:00',
  endTime: '08:10',
  transfers: 0,
  sections: sections,
);

void main() {
  test('firstPoint returns departure of requested leg', () {
    final r = route([
      section(place(25, 121.5), place(25.1, 121.6)),
      section(place(25.1, 121.6), place(25.2, 121.7)),
    ]);
    expect(r.firstPoint(), const PlanPoint(lat: 25, lng: 121.5));
    expect(r.firstPoint(leg: 1), const PlanPoint(lat: 25.1, lng: 121.6));
  });

  test('firstPoint is null for out-of-range leg or zero location', () {
    final r = route([section(place(0, 0), place(25.1, 121.6))]);
    expect(r.firstPoint(), isNull);
    expect(r.firstPoint(leg: 5), isNull);
  });

  test('points flattens sections and drops zero coordinates', () {
    final r = route([
      section(
        place(25, 121.5),
        place(25.2, 121.7),
        stops: [
          const PlanStop(
            name: 's1',
            location: PlanPoint(lat: 25.1, lng: 121.6),
            departureTime: '',
          ),
          const PlanStop(
            name: 'zero',
            location: PlanPoint(lat: 0, lng: 0),
            departureTime: '',
          ),
        ],
      ),
    ]);
    expect(r.points, const [
      PlanPoint(lat: 25, lng: 121.5),
      PlanPoint(lat: 25.1, lng: 121.6),
      PlanPoint(lat: 25.2, lng: 121.7),
    ]);
  });
}
