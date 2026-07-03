import 'package:equatable/equatable.dart';

class BikeStationState extends Equatable {
  const BikeStationState({
    this.name = '',
    this.capacity = 0,
    this.available = 0,
    this.returnDocks = 0,
    this.generalBikes = 0,
    this.electricBikes = 0,
    this.loading = true,
    this.error,
  });

  final String name;
  final int capacity;
  final int available;
  final int returnDocks;
  final int generalBikes;
  final int electricBikes;
  final bool loading;
  final String? error;

  BikeStationState copyWith({
    String? name,
    int? capacity,
    int? available,
    int? returnDocks,
    int? generalBikes,
    int? electricBikes,
    bool? loading,
    String? error,
  }) => BikeStationState(
    name: name ?? this.name,
    capacity: capacity ?? this.capacity,
    available: available ?? this.available,
    returnDocks: returnDocks ?? this.returnDocks,
    generalBikes: generalBikes ?? this.generalBikes,
    electricBikes: electricBikes ?? this.electricBikes,
    loading: loading ?? this.loading,
    error: error,
  );

  @override
  List<Object?> get props => [
    name,
    capacity,
    available,
    returnDocks,
    generalBikes,
    electricBikes,
    loading,
    error,
  ];
}
