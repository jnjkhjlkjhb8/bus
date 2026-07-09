import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/decoders/fare_decoder.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';

BusFareInfo fareWith(String json) => BusFareInfo(
  pricingType: 0,
  isFreeBus: false,
  sectionFaresJson: utf8.encode(json),
  stageFaresJson: const [],
  odFaresJson: const [],
);

const _emptyFare = BusFareInfo(
  pricingType: 0,
  isFreeBus: false,
  sectionFaresJson: [],
  stageFaresJson: [],
  odFaresJson: [],
);

void main() {
  test('extracts buffer stop sequences across sections', () {
    final fare = fareWith(
      jsonEncode([
        {
          'BufferZones': [
            {'StopSequence': 3},
            {'StopSequence': 7},
          ],
        },
        {
          'BufferZones': [
            {'StopSequence': 3},
          ],
        },
      ]),
    );
    expect(decodeBufferSequences(fare), {3, 7});
  });

  test('null fare yields empty set', () {
    expect(decodeBufferSequences(null), isEmpty);
  });

  test('empty payload yields empty set', () {
    expect(decodeBufferSequences(_emptyFare), isEmpty);
  });

  test('malformed json yields empty set', () {
    expect(decodeBufferSequences(fareWith('not json')), isEmpty);
  });

  test('non-list payload yields empty set', () {
    expect(decodeBufferSequences(fareWith('{"a":1}')), isEmpty);
  });

  test('sections without valid buffer zones are skipped', () {
    final fare = fareWith(
      jsonEncode([
        {'Other': 1},
        {'BufferZones': 'nope'},
        {
          'BufferZones': [
            {'StopSequence': 'x'},
            {'StopSequence': 5},
          ],
        },
      ]),
    );
    expect(decodeBufferSequences(fare), {5});
  });

  group('decodeFareTable', () {
    // Shapes mirror real TDX Bus/RouteFare samples: FareClass 1=全票, 10=半票;
    // each entry (section / stage / OD) carries a Fares array of
    // {FareClass, TicketType, Price, FareName?}. Records hold Lists (identity
    // equality), so flatten to nested strings for comparison.
    List<Object?> dump(List<FareGroup> groups) => [
      for (final g in groups)
        [g.segment, [for (final r in g.rows) '${r.label} ${r.price}']],
    ];

    BusFareInfo stageFare(String json) => BusFareInfo(
      pricingType: 2,
      isFreeBus: false,
      sectionFaresJson: const [],
      stageFaresJson: utf8.encode(json),
      odFaresJson: const [],
    );

    test('single section: one flat group, headline classes first', () {
      final fare = fareWith(
        jsonEncode([
          {
            'Fares': [
              {'FareClass': 3, 'TicketType': 1, 'Price': 8},
              {'FareClass': 1, 'TicketType': 1, 'Price': 15},
            ],
          },
        ]),
      );
      expect(dump(decodeFareTable(fare)), [
        [null, [r'全票 NT$15', r'敬老票 NT$8']],
      ]);
    });

    test('splits a class by ticket type only when the price differs', () {
      final fare = fareWith(
        jsonEncode([
          {
            'Fares': [
              {'FareClass': 1, 'TicketType': 1, 'Price': 15},
              {'FareClass': 1, 'TicketType': 3, 'Price': 15},
              {'FareClass': 2, 'TicketType': 1, 'Price': 15},
              {'FareClass': 2, 'TicketType': 3, 'Price': 12},
            ],
          },
        ]),
      );
      expect(dump(decodeFareTable(fare)), [
        [
          null,
          [r'全票 NT$15', r'學生票 NT$15', r'學生票 · 電子票證 NT$12'],
        ],
      ]);
    });

    test('stage fares yield one origin→destination group each', () {
      final fare = stageFare(
        jsonEncode([
          {
            'OriginStage': {'StopName': '大竹消防隊', 'Sequence': 1},
            'DestinationStage': {'StopName': '庫倫街口', 'Sequence': 10},
            'Fares': [
              {'FareName': '全票_不分時段_三排座', 'FareClass': 1, 'Price': 83},
              {'FareName': '半票_不分時段_三排座', 'FareClass': 10, 'Price': 42},
            ],
          },
        ]),
      );
      expect(dump(decodeFareTable(fare)), [
        [
          '大竹消防隊 → 庫倫街口',
          [r'全票 NT$83', r'半票 NT$42'],
        ],
      ]);
    });

    test('drops -1 (no fare) and non-positive prices', () {
      final fare = fareWith(
        jsonEncode([
          {
            'Fares': [
              {'FareClass': 1, 'Price': -1},
              {'FareClass': 10, 'Price': 0},
            ],
          },
        ]),
      );
      expect(decodeFareTable(fare), isEmpty);
    });

    test('unknown fare class falls back to a numbered label', () {
      final fare = fareWith(
        jsonEncode([
          {
            'Fares': [
              {'FareClass': 99, 'Price': 20},
            ],
          },
        ]),
      );
      expect(dump(decodeFareTable(fare)), [
        [null, [r'票種 99 NT$20']],
      ]);
    });

    test('null and malformed payloads yield empty', () {
      expect(decodeFareTable(null), isEmpty);
      expect(decodeFareTable(fareWith('not json')), isEmpty);
      expect(decodeFareTable(_emptyFare), isEmpty);
    });
  });

  group('decodeOdFares', () {
    BusFareInfo odFare(String json) => BusFareInfo(
      pricingType: 1,
      isFreeBus: false,
      sectionFaresJson: const [],
      stageFaresJson: const [],
      odFaresJson: utf8.encode(json),
    );

    List<Object?> dump(List<OdOrigin> origins) => [
      for (final o in origins)
        [
          o.origin,
          [
            for (final d in o.destinations)
              [
                d.destination,
                [for (final r in d.rows) '${r.label} ${r.price}'],
              ],
          ],
        ],
    ];

    final sample = odFare(
      jsonEncode([
        {
          'OriginStop': {'StopName': '統領百貨'},
          'DestinationStop': {'StopName': '慈文國中'},
          'Fares': [
            {'FareClass': 1, 'Price': 18},
          ],
        },
        {
          'OriginStop': {'StopName': '統領百貨'},
          'DestinationStop': {'StopName': '溪洲'},
          'Fares': [
            {'FareClass': 1, 'Price': 27},
          ],
        },
        {
          'OriginStop': {'StopName': '中正橋'},
          'DestinationStop': {'StopName': '崁下'},
          'Fares': [
            {'FareClass': 1, 'Price': 31},
          ],
        },
      ]),
    );

    test('groups destinations under their boarding stop, preserving order', () {
      expect(dump(decodeOdFares(sample)), [
        [
          '統領百貨',
          [
            ['慈文國中', [r'全票 NT$18']],
            ['溪洲', [r'全票 NT$27']],
          ],
        ],
        [
          '中正橋',
          [
            ['崁下', [r'全票 NT$31']],
          ],
        ],
      ]);
    });

    test('entries missing an endpoint are skipped', () {
      final fare = odFare(
        jsonEncode([
          {
            'DestinationStop': {'StopName': '崁下'},
            'Fares': [
              {'FareClass': 1, 'Price': 31},
            ],
          },
        ]),
      );
      expect(decodeOdFares(fare), isEmpty);
    });

    test('flat city-bus fares (no OD payload) yield no origins', () {
      expect(decodeOdFares(fareWith('[{"Fares":[]}]')), isEmpty);
      expect(decodeOdFares(null), isEmpty);
    });

    test('odFareRange spans cheapest to dearest across origins', () {
      expect(odFareRange(decodeOdFares(sample)), (min: 18, max: 31));
    });

    test('odFareRange is null when there are no priced rows', () {
      expect(odFareRange(const []), isNull);
    });
  });
}
