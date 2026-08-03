import 'package:wheres_the_bus/data/repositories/mrt_repository.dart';

/// Seconds until the tracked train reaches the boarding station.
typedef BoardEtaStream =
    Stream<int> Function({
      required String system,
      required String stationId,
      required String trainNumber,
    });

/// The boarding station's own live arrival feed, narrowed to one train.
///
/// A reminder can be armed while the train is still several stations away, and
/// until it pulls in the rider is standing on a platform, not riding. The
/// backend's track session has no notion of that — it starts at the boarding
/// stop and counts outward (see `MrtTrackState.current_index`) — so the
/// pre-board window is answered here, from the same ~15 s arrival feed the
/// station screen already shows. Zero or less means the train is in.
///
/// Frames for other trains at the station are dropped rather than read as an
/// absence: the feed interleaves them, and treating one as "our train is gone"
/// would flip the card back and forth on alternate frames.
///
/// Values pass through exactly as reported — nothing interpolates between
/// frames. A locally ticked countdown keeps falling after the feed has gone
/// quiet, which reads as live data when it is only arithmetic.
Stream<int> defaultBoardEtaStream({
  required String system,
  required String stationId,
  required String trainNumber,
}) {
  if (trainNumber.isEmpty) return const Stream<int>.empty();
  return MrtRepository.instance
      .eta(system, stationId)
      .where((a) => a.trainNumber == trainNumber)
      .map((a) => a.estimateSeconds);
}
