import 'dart:async';

import 'package:wheres_the_car/data/decoders/bus_decoder.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/repositories/bus_repository.dart';

// Station-ETA domain types live in data/models/bus_models.dart; re-exported so
// existing feature imports of this repository keep resolving.
export 'package:wheres_the_car/data/models/bus_models.dart'
    show BusArrivalState, BusStationMember, BusStopArrival;

class BusStopEtaRepository {
  const BusStopEtaRepository._();
  static const instance = BusStopEtaRepository._();

  Future<List<BusStationMember>> members(String groupUid) async {
    if (groupUid == 'B4') return const [];
    final group = await BusRepository.instance.stationGroup(groupUid);
    return BusDecoder.instance.decodeStationMembers(group);
  }

  Stream<List<BusStopArrival>> watchStop(String stopId, {String? city}) async* {
    if (stopId != 'B4') {
      await for (final resp in BusRepository.instance.stationEta(
        city ?? '',
        stopId,
      )) {
        yield BusDecoder.instance.decodeStationEta(resp);
      }
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 550));
    yield _stopArrivalsStub;
  }
}

const _stopArrivalsStub = <BusStopArrival>[
  BusStopArrival(
    stationId: 'B4',
    routeName: '261',
    destination: '銘傳大學',
    state: BusArrivalState.arriving,
  ),
  BusStopArrival(
    stationId: 'B4',
    routeName: '261',
    destination: '桃園火車站',
    state: BusArrivalState.scheduled,
    minutes: 5,
  ),
  BusStopArrival(
    stationId: 'B4',
    routeName: '桃園106',
    destination: '中壢火車站',
    state: BusArrivalState.scheduled,
    minutes: 8,
  ),
  BusStopArrival(
    stationId: 'B4',
    routeName: '桃園106',
    destination: '桃園郵局',
    state: BusArrivalState.arriving,
  ),
  BusStopArrival(
    stationId: 'B4',
    routeName: '桃園130',
    destination: '南崁',
    state: BusArrivalState.scheduled,
    minutes: 12,
  ),
  BusStopArrival(
    stationId: 'B4',
    routeName: '桃園130',
    destination: '桃園火車站',
    state: BusArrivalState.scheduled,
    minutes: 3,
  ),
];
