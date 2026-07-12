import 'package:flutter/widgets.dart';
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart'
    as places;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_car/features/go/model/planned_place.dart';

/// One autocomplete row: a place id plus display text, no coordinates yet.
/// Coordinates come from [PlacesRepository.details] on selection.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;
}

/// Google Places API (New) via the native Android/iOS SDK. Going through the
/// SDK instead of REST lets the API key keep its Android-app restriction: the
/// native request carries the app package + signature the key is locked to,
/// which a plain HTTP call cannot. The session token that bills autocomplete +
/// the follow-up details lookup as one session is managed inside the SDK.
class PlacesRepository {
  PlacesRepository._();
  static final PlacesRepository instance = PlacesRepository._();

  static const _apiKey = String.fromEnvironment('GOOGLE_PLACES_API_KEY');

  /// Null client when no key is configured (e.g. test env) so the UI degrades
  /// to just the current-location option instead of erroring.
  late final places.FlutterGooglePlacesSdk? _client = _apiKey.isEmpty
      ? null
      : places.FlutterGooglePlacesSdk(
          _apiKey,
          locale: const Locale('zh', 'TW'),
          useNewApi: true,
        );

  Future<List<PlaceSuggestion>> autocomplete(String query) async {
    final client = _client;
    if (client == null || query.isEmpty) return const [];
    final res = await client.findAutocompletePredictions(
      query,
      countries: const ['tw'],
    );
    return [
      for (final p in res.predictions)
        PlaceSuggestion(
          placeId: p.placeId,
          primaryText: p.primaryText,
          secondaryText: p.secondaryText,
        ),
    ];
  }

  Future<PlannedPlace> details(String placeId) async {
    final client = _client;
    if (client == null) {
      throw StateError('Places API key not configured');
    }
    final res = await client.fetchPlace(
      placeId,
      fields: const [places.PlaceField.Location, places.PlaceField.Name],
    );
    return plannedPlaceFrom(res.place?.latLng, res.place?.name);
  }

  /// Pure mapper (unit-tested): SDK place location/name -> a [PlannedPlace].
  /// Guards the lat/lng ordering and the missing-location case.
  static PlannedPlace plannedPlaceFrom(places.LatLng? latLng, String? name) {
    if (latLng == null) {
      throw const FormatException('Place details missing location');
    }
    return PlannedPlace(
      name: name ?? '地點',
      latLng: LatLng(latLng.lat, latLng.lng),
    );
  }
}
