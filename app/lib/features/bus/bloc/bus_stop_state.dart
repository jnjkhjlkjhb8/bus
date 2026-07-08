import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';

enum BusStopStatus { loading, loaded, empty, error }

class BusStopState extends Equatable {
  const BusStopState({
    this.status = BusStopStatus.loading,
    this.members = const [],
    this.arrivals = const [],
    this.selectedStationUid,
    this.updatedAt,
    this.error,
  });

  final BusStopStatus status;
  final List<BusStationMember> members;
  final List<BusStopArrival> arrivals;

  /// Selected member stop UID, or null for 全部 (show every member).
  final String? selectedStationUid;
  final DateTime? updatedAt;
  final AppError? error;

  BusStopState copyWith({
    BusStopStatus? status,
    List<BusStationMember>? members,
    List<BusStopArrival>? arrivals,
    String? selectedStationUid,
    bool clearSelection = false,
    DateTime? updatedAt,
    AppError? error,
    bool clearError = false,
  }) => BusStopState(
    status: status ?? this.status,
    members: members ?? this.members,
    arrivals: arrivals ?? this.arrivals,
    selectedStationUid: clearSelection
        ? null
        : (selectedStationUid ?? this.selectedStationUid),
    updatedAt: updatedAt ?? this.updatedAt,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    status,
    members,
    arrivals,
    selectedStationUid,
    updatedAt,
    error,
  ];
}
