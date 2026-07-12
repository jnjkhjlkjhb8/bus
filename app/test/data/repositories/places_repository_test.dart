import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart'
    as places;
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/repositories/places_repository.dart';

void main() {
  group('plannedPlaceFrom', () {
    test('maps SDK lat/lng in the right order and keeps the name', () {
      final place = PlacesRepository.plannedPlaceFrom(
        const places.LatLng(lat: 25.033, lng: 121.5654),
        '台北101',
      );
      expect(place.name, '台北101');
      expect(place.latLng.latitude, 25.033);
      expect(place.latLng.longitude, 121.5654);
    });

    test('falls back to a default name when null', () {
      final place = PlacesRepository.plannedPlaceFrom(
        const places.LatLng(lat: 0, lng: 0),
        null,
      );
      expect(place.name, '地點');
    });

    test('throws when location is missing', () {
      expect(
        () => PlacesRepository.plannedPlaceFrom(null, 'x'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
