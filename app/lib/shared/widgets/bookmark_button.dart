import 'package:flutter/material.dart';
import 'package:wheres_the_bus/data/models/favorite.dart';
import 'package:wheres_the_bus/shared/widgets/sheet_detail_header.dart';

/// Bookmark toggle for a bus route or rail train, keyed by [routeType] and
/// [routeKey]. Delegates the toggle/haptic/undo behavior to
/// [FavoriteToggleButton].
///
/// It deliberately does not touch push subscriptions. The device's 訂閱範圍 is
/// derived from 收藏 and replaced whole by `SubscriptionSync`, so every screen
/// that can add or remove a 收藏 syncs by doing nothing at all.
class BookmarkButton extends StatelessWidget {
  const BookmarkButton({
    required this.routeType,
    required this.routeKey,
    required this.routeLabel,
    this.onPlate = false,
    super.key,
  });

  final String routeType;
  final String routeKey;
  final String routeLabel;

  /// See [FavoriteToggleButton.onPlate].
  final bool onPlate;

  Favorite get _favorite => Favorite(
    type: routeType == 'bus' ? FavoriteType.busRoute : FavoriteType.railTrain,
    refId: routeKey,
    title: routeLabel,
  );

  @override
  Widget build(BuildContext context) =>
      FavoriteToggleButton(favorite: _favorite, onPlate: onPlate);
}
