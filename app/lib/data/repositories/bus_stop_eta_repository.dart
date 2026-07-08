import 'dart:async';

import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/repositories/bus_repository.dart';

// Station-ETA domain types live in data/models/bus_models.dart; re-exported so
// existing feature imports of this repository keep resolving.
export 'package:wheres_the_car/data/models/bus_models.dart'
    show BusStationMember, BusStopArrival;

class BusStopEtaRepository {
  const BusStopEtaRepository._();
  static const instance = BusStopEtaRepository._();

  Future<List<BusStationMember>> members(String groupUid) async {
    if (groupUid.isEmpty) return const [];
    return BusRepository.instance.stationGroup(groupUid);
  }

  Stream<List<BusStopArrival>> watchStop(String stopId, {String? city}) async* {
    if (stopId.isEmpty) return;
    yield* BusRepository.instance.stationEta(city ?? '', stopId);
  }
}
