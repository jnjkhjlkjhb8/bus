import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';

enum PlanStatus { initial, loading, success, failure }

class PlanState extends Equatable {
  const PlanState({
    this.status = PlanStatus.initial,
    this.result,
    this.error,
    this.selectedRouteIndex,
    this.activeLegIndex,
    this.activeStopIndex,
  });

  final PlanStatus status;
  final PlanResult? result;
  final String? error;
  final int? selectedRouteIndex;
  final int? activeLegIndex;
  final int? activeStopIndex;

  PlanState copyWith({
    PlanStatus? status,
    PlanResult? result,
    String? error,
    bool clearError = false,
    int? selectedRouteIndex,
    bool clearNavigation = false,
    int? activeLegIndex,
    int? activeStopIndex,
  }) {
    return PlanState(
      status: status ?? this.status,
      result: result ?? this.result,
      error: clearError ? null : error ?? this.error,
      selectedRouteIndex: selectedRouteIndex ?? this.selectedRouteIndex,
      activeLegIndex: clearNavigation
          ? null
          : activeLegIndex ?? this.activeLegIndex,
      activeStopIndex: clearNavigation
          ? null
          : activeStopIndex ?? this.activeStopIndex,
    );
  }

  @override
  List<Object?> get props => [
    status,
    result,
    error,
    selectedRouteIndex,
    activeLegIndex,
    activeStopIndex,
  ];
}
