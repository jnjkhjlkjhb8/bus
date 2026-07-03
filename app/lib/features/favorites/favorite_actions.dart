import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/shared/widgets/transport_icon.dart';

TransportType transportTypeForFavorite(Favorite fav) {
  switch (fav.type) {
    case FavoriteType.busStop:
      return TransportType.busStop;
    case FavoriteType.busRoute:
      return TransportType.bus;
    case FavoriteType.metroStation:
      return _metroLine(fav.refId);
    case FavoriteType.railStation:
    case FavoriteType.railTrain:
      return TransportType.tra;
    case FavoriteType.bikeStation:
      return TransportType.bike;
  }
}

final RegExp _metroLineSeparator = RegExp(r'[_\d]');

TransportType _metroLine(String id) {
  final code = id.split(_metroLineSeparator).first;
  switch (code) {
    case 'R':
      return TransportType.mrtR;
    case 'G':
      return TransportType.mrtG;
    case 'BR':
      return TransportType.mrtBR;
    case 'O':
      return TransportType.mrtO;
    default:
      return TransportType.mrtBL;
  }
}

void openFavorite(BuildContext context, Favorite fav) {
  switch (fav.type) {
    case FavoriteType.busStop:
      unawaited(context.push('/bus/stop', extra: {'stopName': fav.refId}));
    case FavoriteType.busRoute:
      unawaited(context.push('/bus/route/${fav.refId}'));
    case FavoriteType.metroStation:
      unawaited(context.push('/metro'));
    case FavoriteType.railStation:
    case FavoriteType.railTrain:
      unawaited(context.push('/rail'));
    case FavoriteType.bikeStation:
      unawaited(
        context.push('/bike/station', extra: {'stationUid': fav.refId}),
      );
  }
}
