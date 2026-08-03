import 'package:equatable/equatable.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/data/models/rail_station_board.dart';

/// Every state carries the direction it belongs to, so the segmented control
/// reads its position from the state rather than from a second copy in the
/// view — a request that fails must leave the control where the rider put it.
sealed class RailStationBoardState extends Equatable {
  const RailStationBoardState({required this.direction});

  final RailBoardDirection direction;

  @override
  List<Object?> get props => [direction];
}

final class RailStationBoardLoading extends RailStationBoardState {
  const RailStationBoardLoading({required super.direction});
}

/// The board. An empty [departures] is a real answer, not a failure: the
/// service day is landed and its trains have all gone. A day that was never
/// landed arrives as [RailStationBoardFailure] with a `NotFoundError` instead,
/// and the two say different things to the rider.
final class RailStationBoardLoaded extends RailStationBoardState {
  const RailStationBoardLoaded({
    required super.direction,
    required this.departures,
    this.delays = const {},
  });

  final List<RailStationDeparture> departures;

  /// Live 誤點 minutes by train number, TRA only. Absent means on time.
  final Map<String, int> delays;

  RailStationBoardLoaded copyWith({Map<String, int>? delays}) =>
      RailStationBoardLoaded(
        direction: direction,
        departures: departures,
        delays: delays ?? this.delays,
      );

  @override
  List<Object?> get props => [direction, departures, delays];
}

final class RailStationBoardFailure extends RailStationBoardState {
  const RailStationBoardFailure({
    required super.direction,
    required this.error,
  });

  final AppError error;

  @override
  List<Object?> get props => [direction, error];
}
