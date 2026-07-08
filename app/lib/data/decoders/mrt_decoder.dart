import 'package:wheres_the_car/data/generated/mrt.pb.dart';
import 'package:wheres_the_car/data/models/metro_models.dart';

class MrtDecoder {
  const MrtDecoder._();
  static const MrtDecoder instance = MrtDecoder._();

  MetroLiveArrival decodeEta(Mrt_live live) {
    return MetroLiveArrival(
      line: live.lineID,
      destination: live.destinationStationName,
      estimateSeconds: live.estimateTime,
    );
  }
}
