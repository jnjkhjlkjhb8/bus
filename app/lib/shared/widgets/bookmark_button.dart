import 'package:flutter/material.dart';
import 'package:wheres_the_car/core/firebase/firebase_gate.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/data/repositories/firebase_repository.dart';
import 'package:wheres_the_car/shared/widgets/sheet_detail_header.dart';

/// Bookmark toggle for a bus route or rail train, keyed by [routeType] and
/// [routeKey]. Delegates the toggle/haptic/undo behavior to
/// [FavoriteToggleButton] and additionally syncs the push-notification
/// subscription for route types Firebase tracks.
class BookmarkButton extends StatelessWidget {
  const BookmarkButton({
    required this.routeType,
    required this.routeKey,
    required this.routeLabel,
    super.key,
  });

  final String routeType;
  final String routeKey;
  final String routeLabel;

  Favorite get _favorite => Favorite(
    type: routeType == 'bus' ? FavoriteType.busRoute : FavoriteType.railTrain,
    refId: routeKey,
    title: routeLabel,
  );

  Future<void> _syncFirebaseSubscription(bool added) async {
    if (FirebaseGate.enabled && isFirebaseRouteType(routeType)) {
      try {
        await FirebaseRepository.instance.setRouteSubscription(
          routeType: routeType,
          routeKey: routeKey,
          enabled: added,
        );
      } on Object catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) => FavoriteToggleButton(
    favorite: _favorite,
    onToggled: _syncFirebaseSubscription,
  );
}
