import 'package:wheres_the_bus/data/models/favorite.dart';

/// The line-wide marker a rail-station 收藏 resolves to. It matches no real
/// alert scope, so a subscription holding it receives only the disruptions that
/// name no route — 「台鐵今日全線停駛」reaches it, 「123 次停駛」does not.
const railSystemWideKey = '*';

/// The 訂閱範圍 a set of 收藏 resolves to: the route identities that decide
/// which alerts reach this device, as `'<route_type>:<route_key>'` entries.
/// The same set drives the server-side push subscription and the in-app banner
/// filter, so the two can never disagree about what the rider asked for.
///
/// Not every 收藏 resolves to something. No alert source scopes to a stop, so a
/// bus stop yields nothing (station-level need is served by 到站提醒 and 站點
/// ETA instead), and bike stations have no alert feed at all.
Set<String> subscriptionScope(Iterable<Favorite> favorites) {
  final scope = <String>{};
  for (final favorite in favorites) {
    switch (favorite.type) {
      case FavoriteType.busRoute:
        scope.add('bus:${favorite.refId}');
      case FavoriteType.metroStation:
        scope.addAll(metroStationLines(favorite.refId).map((l) => 'mrt:$l'));
      // A 收藏 does not record which rail system a train or station belongs to,
      // so both are claimed. The wrong one costs nothing: it matches no alert
      // scope, and every rail subscription receives its own system's
      // system-wide disruptions regardless of key.
      case FavoriteType.railTrain:
        scope.addAll(['tra:${favorite.refId}', 'thsr:${favorite.refId}']);
      case FavoriteType.railStation:
        scope.addAll(['tra:$railSystemWideKey', 'thsr:$railSystemWideKey']);
      case FavoriteType.busStop:
      case FavoriteType.bikeStation:
        break;
    }
  }
  return scope;
}

/// The metro lines serving a station, read out of its TDX station id. Ids carry
/// their line code as a prefix and join the codes of an interchange with `_`
/// (`BL15_BR10` is on BL and BR), so no lookup table is needed — but a new line
/// therefore needs an app release, not just a data load.
Iterable<String> metroStationLines(String stationId) sync* {
  for (final segment in stationId.split('_')) {
    final line = segment.replaceAll(RegExp(r'\d+$'), '');
    if (line.isNotEmpty) yield line;
  }
}
