import 'package:wheres_the_bus/core/firebase/firebase_call_options.dart';
import 'package:wheres_the_bus/core/firebase/install_identity.dart';
import 'package:wheres_the_bus/core/grpc/grpc_client.dart';
import 'package:wheres_the_bus/data/generated/mrt.pbgrpc.dart';
import 'package:wheres_the_bus/data/models/mrt_track_models.dart';

/// gRPC seam for the metro alight-reminder session (捷運下車提醒, ADR-0015):
/// CreateTrack resolves a carriage to a trip, WatchTrack streams the evolving
/// position, CancelTrack ends it. Install identity travels the same
/// x-install-id/x-install-secret metadata as the Firebase reminder calls.
class MrtTrackRepository {
  MrtTrackRepository({Mrt_ServiceClient? client}) : _client = client;

  static final MrtTrackRepository instance = MrtTrackRepository();

  static const _system = 'TRTC';

  final Mrt_ServiceClient? _client;
  Mrt_ServiceClient get _grpc => _client ?? GrpcClient.instance.mrt;

  /// Opens a session. Propagates gRPC status errors unchanged so the caller
  /// can distinguish InvalidArgument (train does not reach the target) from
  /// NotFound (car id resolves to no trip).
  Future<MrtTrackSession> createTrack({
    required String carId,
    required String boardStationId,
    required String destStationId,
    required String targetStationId,
    required int leadStops,
  }) async {
    final installId = await InstallIdentity.getOrCreate();
    final state = await _grpc.createTrack(
      CreateMrtTrackRequest(
        installId: installId,
        carId: carId,
        boardStationId: boardStationId,
        destStationId: destStationId,
        targetStationId: targetStationId,
        leadStops: leadStops,
        system: _system,
      ),
      options: await FirebaseCallOptions.build(),
    );
    return _decode(state);
  }

  /// Server-streaming position updates for an open session. Wired through the
  /// resilient stream seam by the bloc; this stays a bare passthrough.
  Stream<MrtTrackSession> watch(String trackId) =>
      _grpc.watchTrack(WatchMrtTrackRequest(trackId: trackId)).map(_decode);

  Future<void> cancel(String trackId) async {
    final installId = await InstallIdentity.getOrCreate();
    await _grpc.cancelTrack(
      CancelMrtTrackRequest(installId: installId, trackId: trackId),
      options: await FirebaseCallOptions.build(),
    );
  }

  MrtTrackSession _decode(MrtTrackState state) => MrtTrackSession(
    trackId: state.trackId,
    tripId: state.tripId,
    carId: state.carId,
    pathStationIds: state.pathStationIds.toList(),
    pathStationNames: state.pathStationNames.toList(),
    targetIndex: state.targetIndex,
    currentIndex: state.currentIndex,
    remainingStops: state.remainingStops,
    nextStationId: state.nextStationId,
    nextStationName: state.nextStationName,
    progress: state.progress,
    status: MrtTrackStatus.fromWire(state.status),
    leadStops: state.leadStops,
    system: state.system.isEmpty ? _system : state.system,
  );
}
