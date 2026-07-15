import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/decoders/alert_decoder.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';

List<int> _bytes(Map<String, dynamic> json) => utf8.encode(jsonEncode(json));

void main() {
  const decoder = AlertDecoder.instance;

  test('extracts title, time and source when present', () {
    final vm = decoder.decode(
      _bytes({
        'Title': '中和新蘆線延誤',
        'Description': '因號誌故障,班距拉長',
        'UpdateTime': '2026-07-12T08:30:00+08:00',
        'Status': 'red',
      }),
      source: const AlertSource(AlertSourceKind.metro, 'TRTC'),
    );

    expect(vm, isNotNull);
    expect(vm!.title, '中和新蘆線延誤');
    expect(vm.message, '因號誌故障,班距拉長');
    expect(vm.level, AlertSeverity.red);
    expect(vm.source, const AlertSource(AlertSourceKind.metro, 'TRTC'));
    expect(vm.time, DateTime.parse('2026-07-12T08:30:00+08:00'));
  });

  test('prefers PublishTime when UpdateTime is absent', () {
    final vm = decoder.decode(
      _bytes({
        'Message': 'x',
        'PublishTime': '2026-07-12T09:00:00Z',
      }),
    );
    expect(vm!.time, DateTime.parse('2026-07-12T09:00:00Z'));
  });

  test('falls back gracefully when enrichment fields are missing', () {
    final vm = decoder.decode(_bytes({'data': '公車改道'}));

    expect(vm, isNotNull);
    expect(vm!.message, '公車改道');
    expect(vm.title, isNull);
    expect(vm.time, isNull);
    expect(vm.source, isNull);
    // Missing Status defaults to yellow.
    expect(vm.level, AlertSeverity.yellow);
  });

  test('tolerates an unparseable time string', () {
    final vm = decoder.decode(
      _bytes({'Message': 'x', 'UpdateTime': 'not-a-date'}),
    );
    expect(vm!.time, isNull);
  });

  test('returns null on malformed payload', () {
    expect(decoder.decode(utf8.encode('not json')), isNull);
  });
}
