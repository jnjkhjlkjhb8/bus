import 'package:equatable/equatable.dart';

class StopBoardState extends Equatable {
  const StopBoardState({this.active = false, this.stopName});

  final bool active;
  final String? stopName;

  @override
  List<Object?> get props => [active, stopName];
}
