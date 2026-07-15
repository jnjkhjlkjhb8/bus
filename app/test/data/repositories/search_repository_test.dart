import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/models/search_models.dart';
import 'package:wheres_the_car/data/repositories/search_repository.dart';

import '../../support/helpers/fake_local_db.dart';

void main() {
  group('offline (HTTP disabled)', () {
    test(
      'finds synchronized static transport data via the local mirror',
      () async {
        final localDb = FakeLocalDb({
          '板橋': [
            {
              'type': 'mrt_station',
              'uid': 'BL13',
              'name': '板橋',
              'city': 'New Taipei',
              'depart': '',
              'destin': '',
            },
          ],
        });
        final repo = SearchRepository(
          localDb: localDb,
          httpFetch: (query, limit) async => throw StateError('HTTP disabled'),
        );

        final results = await repo.search('板橋');

        expect(results, hasLength(1));
        expect(results.single.uid, 'BL13');
        expect(results.single.name, '板橋');
        expect(results.single.type, SearchResultType.mrtStation);
        expect(results.single.subtitle, 'New Taipei');
      },
    );

    test(
      'returns an empty list, not an error, when nothing matches locally',
      () async {
        final repo = SearchRepository(
          localDb: FakeLocalDb(const {}),
          httpFetch: (query, limit) async => throw StateError('HTTP disabled'),
        );

        final results = await repo.search('nowhere');

        expect(results, isEmpty);
      },
    );

    test(
      'drops rail station rows — the rail query flow lives on the home sheet',
      () async {
        final localDb = FakeLocalDb({
          '台北': [
            {
              'type': 'tra_station',
              'uid': '1000',
              'name': '台北',
              'city': 'Taipei',
              'depart': '',
              'destin': '',
            },
          ],
        });
        final repo = SearchRepository(
          localDb: localDb,
          httpFetch: (query, limit) async => throw StateError('HTTP disabled'),
        );

        final results = await repo.search('台北');

        expect(results, isEmpty);
      },
    );
  });

  group('online enrichment', () {
    test(
      'merges local results with HTTP results, local first, deduped',
      () async {
        final localDb = FakeLocalDb({
          'red': [
            {
              'type': 'bus_route',
              'uid': 'local-1',
              'name': 'Red Line',
              'city': 'Taipei',
              'depart': 'A',
              'destin': 'B',
            },
          ],
        });
        final repo = SearchRepository(
          localDb: localDb,
          httpFetch: (query, limit) async => [
            const SearchResult(
              type: SearchResultType.busRoute,
              uid: 'local-1', // duplicate of the local hit
              name: 'Red Line',
              subtitle: 'A → B',
            ),
            const SearchResult(
              type: SearchResultType.busStation,
              uid: 'remote-2',
              name: 'Red Station',
              subtitle: 'Taipei',
            ),
          ],
        );

        final results = await repo.search('red');

        expect(results.map((r) => r.uid), ['local-1', 'remote-2']);
      },
    );

    test('a failing HTTP call still returns the local results', () async {
      final localDb = FakeLocalDb({
        'red': [
          {
            'type': 'bus_route',
            'uid': 'local-1',
            'name': 'Red Line',
            'city': 'Taipei',
            'depart': '',
            'destin': '',
          },
        ],
      });
      final repo = SearchRepository(
        localDb: localDb,
        httpFetch: (query, limit) async => throw StateError('timeout'),
      );

      final results = await repo.search('red');

      expect(results, hasLength(1));
      expect(results.single.uid, 'local-1');
    });
  });
}
