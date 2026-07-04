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
}
