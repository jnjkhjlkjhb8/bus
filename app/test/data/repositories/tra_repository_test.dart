import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:wheres_the_car/data/generated/tra.pbgrpc.dart';
import 'package:wheres_the_car/data/repositories/tra_repository.dart';

import '../../support/helpers/fake_grpc.dart';

void main() {
  test('fare packs the O/D pair into ask_staiton and decodes to a domain fare', () {
    final client = _FakeTraTimetableClient(
      response: TraFareItem(
        originStationId: '1000',
        destinationStationId: '3300',
        ticketType: '成人',
        price: 375,
      ),
    );
    final repo = TraRepository(timetableClient: client);

    // station_id carries the origin, date carries the destination id — matching
    // the router's Fare handler, which reuses ask_staiton to carry the O/D pair.
    return repo.fare('1000', '3300').then((fare) {
      expect(client.request?.stationId, '1000');
      expect(client.request?.date, '3300');
      // Domain type, not the proto TraFareItem.
      expect(fare.price, 375);
      expect(fare.ticketType, '成人');
    });
  });
}

class _FakeTraTimetableClient implements TRA_timetable_serviceClient {
  _FakeTraTimetableClient({required this.response});

  final TraFareItem response;
  ask_staiton? request;

  @override
  ResponseFuture<TraFareItem> fare(
    ask_staiton request, {
    CallOptions? options,
  }) {
    this.request = request;
    return FakeResponseFuture(Future.value(response));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}
