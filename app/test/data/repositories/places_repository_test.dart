import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/repositories/places_repository.dart';

void main() {
  group('parseSuggestions', () {
    test('maps place predictions and skips ones without a place id', () {
      final json = {
        'suggestions': [
          {
            'placePrediction': {
              'placeId': 'abc',
              'structuredFormat': {
                'mainText': {'text': '台北101'},
                'secondaryText': {'text': '台北市信義區'},
              },
            },
          },
          // Category/query guess with no placeId -> dropped.
          {
            'queryPrediction': {
              'text': {'text': '餐廳'},
            },
          },
          {
            'placePrediction': {
              'placeId': 'def',
              'text': {'text': 'Fallback name'},
            },
          },
        ],
      };
      final out = PlacesRepository.parseSuggestions(json);
      expect(out.length, 2);
      expect(out[0].placeId, 'abc');
      expect(out[0].primaryText, '台北101');
      expect(out[0].secondaryText, '台北市信義區');
      // Falls back to prediction text when structuredFormat is absent.
      expect(out[1].primaryText, 'Fallback name');
      expect(out[1].secondaryText, '');
    });

    test('empty or malformed payload yields no rows', () {
      expect(PlacesRepository.parseSuggestions(const {}), isEmpty);
      expect(
        PlacesRepository.parseSuggestions({'suggestions': 'nope'}),
        isEmpty,
      );
    });
  });

  group('parseDetails', () {
    test('reads coordinate and display name', () {
      final place = PlacesRepository.parseDetails({
        'location': {'latitude': 25.033, 'longitude': 121.5654},
        'displayName': {'text': '台北101'},
      });
      expect(place.name, '台北101');
      expect(place.latLng.latitude, 25.033);
      expect(place.latLng.longitude, 121.5654);
    });

    test('throws when location is missing', () {
      expect(
        () => PlacesRepository.parseDetails(const {
          'displayName': {'text': 'x'},
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
