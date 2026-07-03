import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_state.dart';

sealed class MetroEtaEvent extends Equatable {
  const MetroEtaEvent();
  @override
  List<Object?> get props => [];
}

final class LoadMetroEta extends MetroEtaEvent {
  const LoadMetroEta(this.system, this.stationId);
  final String system;
  final String stationId;
  @override
  List<Object?> get props => [system, stationId];
}

final class MetroEtaArrived extends MetroEtaEvent {
  const MetroEtaArrived(this.arrival);
  final MetroArrival arrival;
  @override
  List<Object?> get props => [arrival];
}
