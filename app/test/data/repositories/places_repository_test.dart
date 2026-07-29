import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/data/repositories/places_repository.dart';

void main() {
  group('plannedPlaceFrom', () {
    test('maps lat/lng in the right order and keeps the name', () {
      final place = PlacesRepository.plannedPlaceFrom(
        lat: 25.033,
        lng: 121.5654,
        name: '台北101',
      );
      expect(place.name, '台北101');
      expect(place.latLng.latitude, 25.033);
      expect(place.latLng.longitude, 121.5654);
    });

    test('falls back to a default name when null', () {
      final place = PlacesRepository.plannedPlaceFrom(
        lat: 0,
        lng: 0,
        name: null,
      );
      expect(place.name, '地點');
    });

    test('throws when location is missing', () {
      expect(
        () =>
            PlacesRepository.plannedPlaceFrom(lat: null, lng: null, name: 'x'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('plannedPlaceFromJson', () {
    test('reads location and displayName off a place resource', () {
      final place = PlacesRepository.plannedPlaceFromJson(const {
        'location': {'latitude': 25.033, 'longitude': 121.5654},
        'displayName': {'text': '台北101', 'languageCode': 'zh-TW'},
      });
      expect(place.name, '台北101');
      expect(place.latLng.latitude, 25.033);
      expect(place.latLng.longitude, 121.5654);
    });

    test('throws when the response carries no location', () {
      expect(
        () => PlacesRepository.plannedPlaceFromJson(const {
          'displayName': {'text': '台北101'},
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('suggestionsFromJson', () {
    test('maps structuredFormat into primary/secondary text', () {
      final results = PlacesRepository.suggestionsFromJson(const {
        'suggestions': [
          {
            'placePrediction': {
              'placeId': 'abc',
              'text': {'text': '台北101, 台灣'},
              'structuredFormat': {
                'mainText': {'text': '台北101'},
                'secondaryText': {'text': '台灣台北市'},
              },
            },
          },
        ],
      });
      expect(results, hasLength(1));
      expect(results.single.placeId, 'abc');
      expect(results.single.primaryText, '台北101');
      expect(results.single.secondaryText, '台灣台北市');
    });

    test('falls back to the flat text when structuredFormat is absent', () {
      final results = PlacesRepository.suggestionsFromJson(const {
        'suggestions': [
          {
            'placePrediction': {
              'placeId': 'abc',
              'text': {'text': '台北101'},
            },
          },
        ],
      });
      expect(results.single.primaryText, '台北101');
      expect(results.single.secondaryText, '');
    });

    test('drops entries without a place id and tolerates an empty body', () {
      expect(
        PlacesRepository.suggestionsFromJson(const {
          'suggestions': [
            {
              'queryPrediction': {
                'text': {'text': '咖啡'},
              },
            },
          ],
        }),
        isEmpty,
      );
      expect(PlacesRepository.suggestionsFromJson(const {}), isEmpty);
    });
  });
}
