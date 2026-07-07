import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';

class TraStationState extends Equatable {
  const TraStationState({
    this.items = const [],
    this.loading = false,
    this.error,
  });

  final List<TraLiveBoardItem> items;
  final bool loading;
  final AppError? error;

  TraStationState copyWith({
    List<TraLiveBoardItem>? items,
    bool? loading,
    AppError? error,
  }) => TraStationState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    error: error,
  );

  @override
  List<Object?> get props => [items, loading, error];
}
