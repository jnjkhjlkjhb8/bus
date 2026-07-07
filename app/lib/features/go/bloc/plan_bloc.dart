import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/data/repositories/maas_repository.dart';
import 'package:wheres_the_car/features/go/bloc/plan_event.dart';
import 'package:wheres_the_car/features/go/bloc/plan_state.dart';

class PlanBloc extends Bloc<PlanEvent, PlanState> {
  PlanBloc({MaasRepository repository = MaasRepository.instance})
    : _repository = repository,
      super(const PlanState()) {
    on<PlanSearchRequested>(_onSearch);
    on<RouteSelected>(_onRouteSelected);
    on<NavigationStarted>(_onNavigationStarted);
    on<StopArrived>(_onStopArrived);
    on<NavigationEnded>(_onNavigationEnded);
  }

  final MaasRepository _repository;

  Future<void> _onSearch(
    PlanSearchRequested event,
    Emitter<PlanState> emit,
  ) async {
    emit(state.copyWith(status: PlanStatus.loading, clearError: true));
    try {
      final result = await _repository.plan(
        fromLat: event.fromLat,
        fromLon: event.fromLon,
        toLat: event.toLat,
        toLon: event.toLon,
        date: event.date,
        time: event.time,
        arriveBy: event.arriveBy,
        gc: event.gc,
        transitModes: event.transitModes,
        top: event.top,
        transferMin: event.transferMin,
        transferMax: event.transferMax,
        firstMileMode: event.firstMileMode,
        firstMileTime: event.firstMileTime,
        lastMileMode: event.lastMileMode,
        lastMileTime: event.lastMileTime,
      );
      emit(state.copyWith(status: PlanStatus.success, result: result));
    } on Object catch (e) {
      emit(
        state.copyWith(
          status: PlanStatus.failure,
          error: e.toString(),
        ),
      );
    }
  }

  void _onRouteSelected(RouteSelected event, Emitter<PlanState> emit) {
    emit(state.copyWith(selectedRouteIndex: event.index));
  }

  void _onNavigationStarted(NavigationStarted _, Emitter<PlanState> emit) {
    emit(state.copyWith(activeLegIndex: 0, activeStopIndex: 0));
  }

  void _onStopArrived(StopArrived event, Emitter<PlanState> emit) {
    emit(
      state.copyWith(
        activeLegIndex: event.legIndex,
        activeStopIndex: event.stopIndex,
      ),
    );
  }

  void _onNavigationEnded(NavigationEnded _, Emitter<PlanState> emit) {
    emit(state.copyWith(clearNavigation: true));
  }
}
