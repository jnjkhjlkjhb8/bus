import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:wheres_the_car/data/generated/thsr.pbgrpc.dart';
import 'package:wheres_the_car/data/repositories/thsr_repository.dart';

import '../../support/helpers/fake_grpc.dart';

void main() {
  test('fare builds the Ask_Thsr request and decodes to a domain fare', () {
    final client = _FakeThsrTimetableClient(
      response: thsa_fare(
        originStationId: '1000',
        destinationStationId: '1070',
        ticketType: 1,
        fareClass: 0,
        price: 1490,
      ),
    );
    final repo = ThsrRepository(timetableClient: client);

    return repo.fare('2026-07-09', '1000', '1070').then((fare) {
      expect(client.request?.originStationId, '1000');
      expect(client.request?.destinationStationId, '1070');
      expect(client.request?.date, '2026-07-09');
      // Domain type, not the proto thsa_fare.
      expect(fare.price, 1490);
      expect(fare.fareClass, 0);
    });
  });
}

class _FakeThsrTimetableClient implements Thsr_timetable_serviceClient {
  _FakeThsrTimetableClient({required this.response});

  final thsa_fare response;
  Ask_Thsr? request;

  @override
  ResponseFuture<thsa_fare> fare(Ask_Thsr request, {CallOptions? options}) {
    this.request = request;
    return FakeResponseFuture(Future.value(response));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}
