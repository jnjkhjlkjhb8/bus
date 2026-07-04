import 'package:equatable/equatable.dart';

/// One live metro arrival estimate. estimateSeconds is raw; callers apply
/// etaCeilMinutes (eta_format.dart) for display so the ceil rule has one owner.
class MetroLiveArrival extends Equatable {
  const MetroLiveArrival({
    required this.line,
    required this.destination,
    required this.estimateSeconds,
  });

  final String line;
  final String destination;
  final int estimateSeconds;

  @override
  List<Object?> get props => [line, destination, estimateSeconds];
}
