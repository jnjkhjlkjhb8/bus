import 'package:flutter/material.dart';
import 'package:wheres_the_car/core/firebase/firebase_gate.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/data/repositories/favorites_repository.dart';
import 'package:wheres_the_car/data/repositories/firebase_repository.dart';

class BookmarkButton extends StatefulWidget {
  const BookmarkButton({
    required this.routeType,
    required this.routeKey,
    required this.routeLabel,
    super.key,
  });

  final String routeType;
  final String routeKey;
  final String routeLabel;

  @override
  State<BookmarkButton> createState() => _BookmarkButtonState();
}

class _BookmarkButtonState extends State<BookmarkButton> {
  late bool _saved;

  Favorite get _favorite => Favorite(
    type: widget.routeType == 'bus'
        ? FavoriteType.busRoute
        : FavoriteType.railTrain,
    refId: widget.routeKey,
    title: widget.routeLabel,
  );

  @override
  void initState() {
    super.initState();
    _saved = FavoritesRepository.instance.isFavorite(_favorite.id);
  }

  Future<void> _toggle() async {
    final added = await FavoritesRepository.instance.toggle(_favorite);
    if (FirebaseGate.enabled && isFirebaseRouteType(widget.routeType)) {
      try {
        await FirebaseRepository.instance.setRouteSubscription(
          routeType: widget.routeType,
          routeKey: widget.routeKey,
          enabled: added,
        );
      } on Object catch (_) {}
    }
    if (mounted) setState(() => _saved = added);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: _saved ? '取消收藏' : '加入收藏',
    icon: Icon(_saved ? Icons.bookmark_rounded : Icons.bookmark_add_rounded),
    onPressed: _toggle,
  );
}
