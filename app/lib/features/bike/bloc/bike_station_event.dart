import 'package:equatable/equatable.dart';

sealed class BikeStationEvent extends Equatable {
  const BikeStationEvent();
  @override
  List<Object?> get props => [];
}

final class BikeStationStarted extends BikeStationEvent {
  const BikeStationStarted();
}

final class BikeStationEtaUpdated extends BikeStationEvent {
  const BikeStationEtaUpdated({
    required this.available,
    required this.returnDocks,
    required this.generalBikes,
    required this.electricBikes,
  });
  final int available;
  final int returnDocks;
  final int generalBikes;
  final int electricBikes;
  @override
  List<Object?> get props =>
      [available, returnDocks, generalBikes, electricBikes];
}
