import 'dart:typed_data';
import 'package:wheres_the_car/data/generated/mrt.pb.dart';

class MrtDecoder {
  const MrtDecoder._();
  static const MrtDecoder instance = MrtDecoder._();

  Mrt_live decodeEta(Uint8List data) => Mrt_live.fromBuffer(data);
}
