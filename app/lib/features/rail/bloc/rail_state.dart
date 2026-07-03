import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart' show TimeOfDay;
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

final class RailLiveBoardLoading extends RailState {
  const RailLiveBoardLoading({
    required this.system,
    required this.stationId,
    required this.stationName,
  });
  final RailSystem system;
  final String stationId;
  final String stationName;
  @override
  List<Object?> get props => [system, stationId, stationName];
}

final class RailLiveBoardLoaded extends RailState {
  const RailLiveBoardLoaded({
    required this.system,
    required this.stationId,
    required this.stationName,
    required this.traItems,
    required this.queryOriginId,
    required this.queryOriginName,
    required this.queryDestId,
    required this.queryDestName,
    required this.queryDate,
    required this.queryTime,
    required this.departureMode,
  });

  final RailSystem system;
  final String stationId;
  final String stationName;
  final List<TraLiveBoardItem> traItems;

  final String queryOriginId;
  final String queryOriginName;
  final String queryDestId;
  final String queryDestName;
  final DateTime queryDate;
  final TimeOfDay queryTime;
  final bool departureMode;

  RailLiveBoardLoaded copyWith({
    RailSystem? system,
    String? stationId,
    String? stationName,
    List<TraLiveBoardItem>? traItems,
    String? queryOriginId,
    String? queryOriginName,
    String? queryDestId,
    String? queryDestName,
    DateTime? queryDate,
    TimeOfDay? queryTime,
    bool? departureMode,
  }) => RailLiveBoardLoaded(
    system: system ?? this.system,
    stationId: stationId ?? this.stationId,
    stationName: stationName ?? this.stationName,
    traItems: traItems ?? this.traItems,
    queryOriginId: queryOriginId ?? this.queryOriginId,
    queryOriginName: queryOriginName ?? this.queryOriginName,
    queryDestId: queryDestId ?? this.queryDestId,
    queryDestName: queryDestName ?? this.queryDestName,
    queryDate: queryDate ?? this.queryDate,
    queryTime: queryTime ?? this.queryTime,
    departureMode: departureMode ?? this.departureMode,
  );

  @override
  List<Object?> get props => [
    system,
    stationId,
    stationName,
    traItems,
    queryOriginId,
    queryOriginName,
    queryDestId,
    queryDestName,
    queryDate,
    queryTime,
    departureMode,
  ];
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
  });
  final RailSystem system;
  final String originName;
  final String destName;
  final String date;
  final List<TraTimetableItem> traItems;
  final List<ThsrTimetableItem> thsrItems;
  final Map<String, int> delays;

  RailTimetableLoaded copyWith({
    RailSystem? system,
    String? originName,
    String? destName,
    String? date,
    List<TraTimetableItem>? traItems,
    List<ThsrTimetableItem>? thsrItems,
    Map<String, int>? delays,
  }) => RailTimetableLoaded(
    system: system ?? this.system,
    originName: originName ?? this.originName,
    destName: destName ?? this.destName,
    date: date ?? this.date,
    traItems: traItems ?? this.traItems,
    thsrItems: thsrItems ?? this.thsrItems,
    delays: delays ?? this.delays,
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
