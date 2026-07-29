import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/data/models/bike_models.dart';

void main() {
  test('BikeAvailability sums general and electric into available', () {
    const a = BikeAvailability(
      generalBikes: 3,
      electricBikes: 2,
      returnDocks: 7,
    );
    expect(a.available, 5);
    expect(a.returnDocks, 7);
  });

  test('BikeStationInfo carries name, capacity, and coordinates', () {
    const s = BikeStationInfo(
      name: 'YouBike 大安',
      capacity: 30,
      lat: 25.033,
      lon: 121.565,
    );
    expect(s.name, 'YouBike 大安');
    expect(s.capacity, 30);
    expect(s.lat, 25.033);
    expect(s.lon, 121.565);
  });
}
