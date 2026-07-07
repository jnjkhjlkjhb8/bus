import 'package:equatable/equatable.dart';

sealed class RailTrainEvent extends Equatable {
  const RailTrainEvent();

  @override
  List<Object?> get props => [];
}

/// Loads (or reloads, on retry) the train's stops and fare.
class RailTrainStarted extends RailTrainEvent {
  const RailTrainStarted();
}
