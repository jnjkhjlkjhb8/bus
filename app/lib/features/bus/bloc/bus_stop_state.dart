import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/arrival_display.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';

enum BusStopStatus { loading, loaded, empty, error }

/// One arrival mapped to the shared tile contract ([ArrivalDisplay]) plus the
/// routing identifiers the stop sheet still needs: [stationId] for per-stop
/// grouping and [subRouteUid] for the tap target. The map/sort/group derivation
/// runs in the bloc when arrivals change, so the sheet build stays pure layout.
/// Equality flows from the source arrival (itself Equatable), keeping items
/// stable across an unchanged re-push.
class BusStopArrivalItem extends Equatable {
  BusStopArrivalItem(this.source)
    : display = ArrivalDisplay.fromBusStop(source);

  final BusStopArrival source;
  final ArrivalDisplay display;

  String get stationId => source.stationId;
  String get subRouteUid => source.subRouteUid;
  int get rank => display.rank;

  /// Stable per-arrival identity for list keys: a route (sub-route) at a member
  /// stop. Keeps StaggerItem element↔State pairing correct across a re-sort.
  String get itemKey => '$stationId:$subRouteUid';

  @override
  List<Object?> get props => [source];
}

class BusStopState extends Equatable {
  const BusStopState({
    this.status = BusStopStatus.loading,
    this.members = const [],
    this.arrivals = const [],
    this.displays = const [],
    this.arrivalsByStation = const {},
    this.selectedStationUid,
    this.updatedAt,
    this.error,
  });

  final BusStopStatus status;
  final List<BusStationMember> members;
  final List<BusStopArrival> arrivals;

  /// Sorted (soonest first) tile view-models, derived from [arrivals] in the
  /// bloc. Deterministic from [arrivals], so it stays out of [props].
  final List<BusStopArrivalItem> displays;

  /// [displays] grouped by member stop (keyed by arrival stationId, which pairs
  /// with member stationUid). Also derived, also out of [props].
  final Map<String, List<BusStopArrivalItem>> arrivalsByStation;

  /// Selected member stop UID, or null for 全部 (show every member).
  final String? selectedStationUid;
  final DateTime? updatedAt;
  final AppError? error;

  BusStopState copyWith({
    BusStopStatus? status,
    List<BusStationMember>? members,
    List<BusStopArrival>? arrivals,
    List<BusStopArrivalItem>? displays,
    Map<String, List<BusStopArrivalItem>>? arrivalsByStation,
    String? selectedStationUid,
    bool clearSelection = false,
    DateTime? updatedAt,
    AppError? error,
    bool clearError = false,
  }) => BusStopState(
    status: status ?? this.status,
    members: members ?? this.members,
    arrivals: arrivals ?? this.arrivals,
    displays: displays ?? this.displays,
    arrivalsByStation: arrivalsByStation ?? this.arrivalsByStation,
    selectedStationUid: clearSelection
        ? null
        : (selectedStationUid ?? this.selectedStationUid),
    updatedAt: updatedAt ?? this.updatedAt,
    error: clearError ? null : (error ?? this.error),
  );

  // [displays] and [arrivalsByStation] are a deterministic function of
  // [arrivals], so they are omitted here — including them would just re-run the
  // same equality over derived data.
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
