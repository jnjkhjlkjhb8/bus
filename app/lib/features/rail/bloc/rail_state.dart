import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/thsr_models.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';

sealed class RailState extends Equatable {
  const RailState();
  @override
  List<Object?> get props => [];
}

final class RailInitial extends RailState {
  const RailInitial();
}

final class RailTimetableLoading extends RailState {
  const RailTimetableLoading({
    required this.system,
    required this.originName,
    required this.destName,
    required this.date,
  });
  final RailSystem system;
  final String originName;
  final String destName;
  final String date;
  @override
  List<Object?> get props => [system, originName, destName, date];
}

final class RailTimetableLoaded extends RailState {
  const RailTimetableLoaded({
    required this.system,
    required this.originName,
    required this.destName,
    required this.date,
    this.traItems = const [],
    this.thsrItems = const [],
    this.delays = const {},
    this.fare,
  });
  final RailSystem system;
  final String originName;
  final String destName;
  final String date;
  final List<TraTimetableItem> traItems;
  final List<ThsrTimetableItem> thsrItems;
  final Map<String, int> delays;

  /// Adult (全票) fare in NT$ for this O/D pair, or null when the fare query
  /// had no data. TRA/THSR fares are per O/D, not per train, so every card in
  /// the list shares this value.
  final int? fare;

  RailTimetableLoaded copyWith({
    RailSystem? system,
    String? originName,
    String? destName,
    String? date,
    List<TraTimetableItem>? traItems,
    List<ThsrTimetableItem>? thsrItems,
    Map<String, int>? delays,
    int? fare,
  }) => RailTimetableLoaded(
    system: system ?? this.system,
    originName: originName ?? this.originName,
    destName: destName ?? this.destName,
    date: date ?? this.date,
    traItems: traItems ?? this.traItems,
    thsrItems: thsrItems ?? this.thsrItems,
    delays: delays ?? this.delays,
    fare: fare ?? this.fare,
  );

  @override
  List<Object?> get props => [
    system,
    originName,
    destName,
    date,
    traItems,
    thsrItems,
    delays,
    fare,
  ];
}

final class RailTrainStopsLoaded extends RailState {
  const RailTrainStopsLoaded({
    required this.system,
    required this.trainNo,
    required this.trainType,
    this.traStops = const [],
    this.thsrStops = const [],
  });
  final RailSystem system;
  final String trainNo;
  final String trainType;
  final List<TraStopTime> traStops;
  final List<ThsrStopTime> thsrStops;
  @override
  List<Object?> get props => [system, trainNo, trainType, traStops, thsrStops];
}

final class RailError extends RailState {
  const RailError(this.error);

  final AppError error;

  @override
  List<Object?> get props => [error];
}
