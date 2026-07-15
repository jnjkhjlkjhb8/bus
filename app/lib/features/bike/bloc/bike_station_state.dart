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
    this.hasLiveData = false,
    this.error,
    this.liveError,
  });

  final String name;
  final int capacity;
  final int available;
  final int returnDocks;
  final int generalBikes;
  final int electricBikes;
  final bool loading;

  /// Whether at least one live ETA frame has been received. `available == 0`
  /// is a legitimate reading once this is true; while it's false, the zero
  /// shown is only the field default, not a confirmed empty station (F27).
  final bool hasLiveData;

  /// Static station-info fetch failure (name/capacity never loaded).
  final String? error;

  /// Live availability stream failure, surfaced after the underlying
  /// ResilientSubscription gives up reconnecting; cleared only on recovery.
  /// Kept separate from [error] so a static-info success doesn't mask a live
  /// stream that never came up, and vice versa (F27).
  final String? liveError;

  BikeStationState copyWith({
    String? name,
    int? capacity,
    int? available,
    int? returnDocks,
    int? generalBikes,
    int? electricBikes,
    bool? loading,
    bool? hasLiveData,
    String? error,
    bool clearError = false,
    String? liveError,
    bool clearLiveError = false,
  }) => BikeStationState(
    name: name ?? this.name,
    capacity: capacity ?? this.capacity,
    available: available ?? this.available,
    returnDocks: returnDocks ?? this.returnDocks,
    generalBikes: generalBikes ?? this.generalBikes,
    electricBikes: electricBikes ?? this.electricBikes,
    loading: loading ?? this.loading,
    hasLiveData: hasLiveData ?? this.hasLiveData,
    error: clearError ? null : (error ?? this.error),
    liveError: clearLiveError ? null : (liveError ?? this.liveError),
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
    hasLiveData,
    error,
    liveError,
  ];
}
