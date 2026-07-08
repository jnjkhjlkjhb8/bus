import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/decoders/mrt_decoder.dart';
import 'package:wheres_the_car/data/generated/mrt.pb.dart';
import 'package:wheres_the_car/data/models/metro_models.dart';

const MrtDecoder _decoder = MrtDecoder.instance;

void main() {
  group('decodeEta', () {
    test('a fully-populated Mrt_live decodes to the expected view model', () {
      final live = Mrt_live(
        lineID: 'BR',
        stationID: 'BR01',
        destinationStationName: '南港展覽館',
        estimateTime: 120,
      );
      final out = _decoder.decodeEta(live);
      expect(
        out,
        const MetroLiveArrival(
          line: 'BR',
          destination: '南港展覽館',
          estimateSeconds: 120,
        ),
      );
    });

    // Proto3 default instances are never null: resp.data on an empty message
    // always returns a zero-valued sub-message. This is the crash-guard
    // case -- a race can deliver a near-empty frame and decodeEta must not
    // throw.
    test('a default-constructed Mrt_live decodes without throwing', () {
      final out = _decoder.decodeEta(Mrt_live());
      expect(
        out,
        const MetroLiveArrival(line: '', destination: '', estimateSeconds: 0),
      );
    });

    test('zero estimateTime decodes to a zero countdown', () {
      final out = _decoder.decodeEta(
        Mrt_live(lineID: 'BL', destinationStationName: '頂溪', estimateTime: 0),
      );
      expect(out.estimateSeconds, 0);
    });

    // decodeEta passes estimateTime straight through with no clamp -- unlike
    // the bus/TRA decoders, which derive their countdowns via
    // etaRemainingSeconds (which does clamp negatives to 0). Pinning this
    // as current behavior, not a fix: if TDX ever sends a negative
    // EstimateTime, callers see a negative countdown.
    test(
      'a negative estimateTime passes through unclamped (no derivation)',
      () {
        final out = _decoder.decodeEta(
          Mrt_live(lineID: 'BL', estimateTime: -30),
        );
        expect(out.estimateSeconds, -30);
      },
    );
  });
}
