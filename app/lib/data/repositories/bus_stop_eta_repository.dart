import 'dart:async';

import 'package:wheres_the_car/data/generated/bus.pb.dart';
import 'package:wheres_the_car/data/repositories/bus_repository.dart';

enum BusArrivalState { arriving, scheduled, unknown }

class BusStationMember {
  const BusStationMember({
    required this.stationUid,
    required this.stationId,
    required this.stationName,
    required this.lat,
    required this.lon,
  });

  final String stationUid;
  final String stationId;
  final String stationName;
  final double lat;
  final double lon;
}

class BusStopArrival {
  const BusStopArrival({
    required this.stationId,
    required this.routeName,
    required this.destination,
    required this.state,
    this.minutes,
  });

  final String stationId;
  final String routeName;
  final String destination;
  final BusArrivalState state;
  final int? minutes;
}

class BusStopEtaRepository {
  const BusStopEtaRepository._();
  static const instance = BusStopEtaRepository._();

  Future<List<BusStationMember>> members(String groupUid) async {
    if (groupUid == 'B4') return const [];
    final group = await BusRepository.instance.stationGroup(groupUid);
    return group.members.map((m) {
      return BusStationMember(
        stationUid: m.stationUid,
        stationId: m.stationId,
        stationName: m.stationName,
        lat: m.positionLat,
        lon: m.positionLon,
      );
    }).toList();
  }

  Stream<List<BusStopArrival>> watchStop(String stopId, {String? city}) async* {
    if (stopId != 'B4') {
      final key = city == null || city.isEmpty ? stopId : '$city:$stopId';
      await for (final resp in BusRepository.instance.stationEtaKey(key)) {
        yield _decode(resp);
      }
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 550));
    yield _stopArrivalsStub;
  }

  List<BusStopArrival> _decode(Resp_Bus_eta resp) {
    final arrival = Bus_StationArrival.fromBuffer(resp.data);
    return arrival.routes.map((r) {
      final minutes = r.estimate > 0 ? (r.estimate / 60).ceil() : null;
      final state = switch (r.stopStatus) {
        0 when minutes != null => BusArrivalState.scheduled,
        1 => BusArrivalState.arriving,
        _ => BusArrivalState.unknown,
      };
      return BusStopArrival(
        stationId: r.stopUid,
        routeName: r.routeName,
        destination: r.direction == 1 ? '返程' : '去程',
        state: state,
        minutes: minutes,
      );
    }).toList();
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
