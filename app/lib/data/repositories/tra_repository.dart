import 'package:wheres_the_bus/core/grpc/grpc_client.dart';
import 'package:wheres_the_bus/data/decoders/tra_decoder.dart';
import 'package:wheres_the_bus/data/generated/tra.pbgrpc.dart';
import 'package:wheres_the_bus/data/models/rail_station_board.dart';
import 'package:wheres_the_bus/data/models/tra_models.dart';
import 'package:wheres_the_bus/data/repositories/offline_cache.dart';

class TraRepository {
  TraRepository({
    TRA_timetable_serviceClient? timetableClient,
    TRA_Detain_serviceClient? detainClient,
  }) : _timetableClient = timetableClient,
       _detainClient = detainClient;

  static final TraRepository instance = TraRepository();

  TRA_timetable_serviceClient? _timetableClient;
  TRA_timetable_serviceClient get _timetable =>
      _timetableClient ??= GrpcClient.instance.traTimetable;

  TRA_Detain_serviceClient? _detainClient;
  TRA_Detain_serviceClient get _detain =>
      _detainClient ??= GrpcClient.instance.traDetain;

  Future<List<TraTimetableItem>> timetable(
    String date,
    String originId,
    String destId,
  ) => offlineCached(
    key: 'd:$date:tra:tt:$originId:$destId',
    fetch: () => _timetable.timetable(
      ask_route(
        date: date,
        originStationId: originId,
        destinationStationId: destId,
      ),
    ),
    parse: tra_timetables.fromBuffer,
    decode: TraDecoder.instance.decodeTimetable,
  );

  /// The next departures from one station in one direction — the board a rider
  /// gets by tapping the station on the map, with no destination to pick.
  ///
  /// [after] is the rider's own `HH:mm:ss`, not the server's: the router runs
  /// in UTC. The offline key deliberately omits it, so a rider who loses signal
  /// mid-journey still sees the last board they pulled rather than a miss on a
  /// minute nobody has queried before.
  Future<List<RailStationDeparture>> stationBoard({
    required String stationId,
    required String date,
    required String after,
    required RailBoardDirection direction,
  }) => offlineCached(
    key: 'd:$date:tra:board:$stationId:${direction.wire}',
    fetch: () => _timetable.station_board(
      ask_station_board(
        stationId: stationId,
        date: date,
        after: after,
        direction: direction.wire,
      ),
    ),
    parse: tra_station_board.fromBuffer,
    decode: TraDecoder.instance.decodeStationBoard,
  );

  /// Adult fares for an origin→destination pair, one per train class — a TRA
  /// fare depends on the class of train taken, so use `traFareFor` to
  /// pick the one that prices a given train. `ask_staiton` carries the pair
  /// across its two string fields — station_id is the origin, date is the
  /// destination id — matching the router's Fare handler (TRA fares are per
  /// O/D, not per date). The router resolves station names to ids, so plain
  /// station names are valid arguments too.
  Future<List<TraFare>> fares(String originId, String destId) => offlineCached(
    key: 's:tra:fare:$originId:$destId',
    fetch: () =>
        _timetable.fare(ask_staiton(stationId: originId, date: destId)),
    parse: tra_fare_items.fromBuffer,
    decode: TraDecoder.instance.decodeFares,
  );

  /// Server-streaming: emits decoded delay data (trainNo → delay minutes) for
  /// trains on the [originId]→[destId] segment on [date].
  Stream<Map<String, int>> delay(
    String date,
    String originId,
    String destId,
  ) => _timetable
      .delay(
        ask_route(
          date: date,
          originStationId: originId,
          destinationStationId: destId,
        ),
      )
      .map(
        (resp) => Map<String, int>.from(
          TraDecoder.instance.decodeDelayMap(resp.data),
        ),
      );

  Future<List<TraStopTime>> stops(String date, String trainNo) => offlineCached(
    key: 'd:$date:tra:stops:$trainNo',
    fetch: () => _detain.stops(ask_detain(date: date, trainno: trainNo)),
    parse: tra_stoptimes.fromBuffer,
    decode: TraDecoder.instance.decodeStops,
  );
}
