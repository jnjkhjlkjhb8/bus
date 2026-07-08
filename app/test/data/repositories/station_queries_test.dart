import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/repositories/mrt_repository.dart';
import 'package:wheres_the_car/data/repositories/thsr_repository.dart';
import 'package:wheres_the_car/data/repositories/tra_repository.dart';

import '../../support/helpers/fake_local_db.dart';

void main() {
  group('TraRepository.stationId', () {
    test('resolves a known station name to its id', () async {
      final repo = TraRepository(
        localDb: FakeLocalDb({
          '台北': [
            {'station_id': '1000'},
          ],
        }),
      );
      expect(await repo.stationId('台北'), '1000');
    });

    test('returns null for an unknown name', () async {
      final repo = TraRepository(localDb: FakeLocalDb({}));
      expect(await repo.stationId('不存在'), isNull);
    });
  });

  group('ThsrRepository.stationId', () {
    test('resolves a known station name to its id', () async {
      final repo = ThsrRepository(
        localDb: FakeLocalDb({
          '左營': [
            {'station_id': '2000'},
          ],
        }),
      );
      expect(await repo.stationId('左營'), '2000');
    });

    test('returns null for an unknown name', () async {
      final repo = ThsrRepository(localDb: FakeLocalDb({}));
      expect(await repo.stationId('不存在'), isNull);
    });
  });

  group('MrtRepository local queries', () {
    test('schedule maps rows to schedule entries', () async {
      final repo = MrtRepository(
        localDb: FakeLocalDb({
          'BL12': [
            {
              'destinationstaionid': 'BL01',
              'first_train_time': '06:00',
              'last_train_time': '00:00',
            },
          ],
        }),
      );
      final schedule = await repo.schedule('BL12');
      expect(schedule, hasLength(1));
      expect(schedule.first.destination, 'BL01');
      expect(schedule.first.firstTime, '06:00');
      expect(schedule.first.lastTime, '00:00');
    });

    test('journeyMatrix keys rows by destination station id', () async {
      final repo = MrtRepository(
        localDb: FakeLocalDb({
          'BL12': [
            {'to_station_id': 'BL01', 'fare_nt': 20},
            {'to_station_id': 'BL02', 'fare_nt': 25},
          ],
        }),
      );
      final matrix = await repo.journeyMatrix('BL12');
      expect(matrix.keys, containsAll(['BL01', 'BL02']));
      expect(matrix['BL02']?.fareNt, 25);
    });

    test('empty result yields empty schedule and matrix', () async {
      final repo = MrtRepository(localDb: FakeLocalDb({}));
      expect(await repo.schedule('nope'), isEmpty);
      expect(await repo.journeyMatrix('nope'), isEmpty);
    });
  });
}
